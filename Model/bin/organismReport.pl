#!/usr/bin/perl

use strict;

use DBI;
use DBD::Oracle;
use Getopt::Long;

use XML::Simple;

use Data::Dumper;

my ($help, $project, $instance);

&GetOptions('help|h' => \$help,
            'project=s' => \$project,
            'instance=s' => \$instance,
    );

if($help || !$project || !$instance) {
  print "usage:  organismReport -project <PROJECT=s> -instance <INSTANCE=s>\n";
  exit;
}


my $fn = $ENV{PROJECT_HOME} . "/ApiCommonPresenters/Model/lib/xml/datasetPresenters/$project.xml";

my $xml = XMLin($fn, ForceArray => 1);

my $dbh = DBI->connect("dbi:Oracle:$instance") or die DBI->errstr;
$dbh->{RaiseError} = 1;
$dbh->{AutoCommit} = 0;


my $sql = "select tn.name as organism, o.is_annotated_genome, listagg(ds.name, ',') within group (order by ds.name) as datasets
from apidb.organism o, sres.taxonname tn,   
  apidb.datasource ds
where o.taxon_id = tn.taxon_id
and tn.name_class = 'scientific name'
and ds.taxon_id = o.taxon_id
and ds.type = 'genome'
group by tn.name, o.is_annotated_genome
order by is_annotated_genome, tn.name";

my $sh = $dbh->prepare($sql);
$sh->execute();


while(my ($organism, $isAnnotated, $datasets) = $sh->fetchrow_array()) {
  my $expected = $isAnnotated ? "AnnotatedGenome" : "UnannotatedGenome";

  #foreach $datasets .. check if we h at least one dsp
  my @datasets = split(",", $datasets);

  my $missingAttribution = 1;
  foreach my $dataset(@datasets) {
    if(my $dsXml = $xml->{datasetPresenter}->{$dataset}) {
      $missingAttribution = 0;

      my $injector = $dsXml->{templateInjector}->[0]->{className};
      if($injector) {
        if($isAnnotated && $injector ne 'org.apidb.apicommon.model.datasetInjector.AnnotatedGenome') {
          print "$project\t$datasets\t$organism\tExpected $expected\tIncorrect Injector $injector\n";
        }
        if(!$isAnnotated && $injector ne 'org.apidb.apicommon.model.datasetInjector.UnannotatedGenome') {
          print "$project\t$datasets\t$organism\tExpected $expected\tIncorrect Injector $injector\n";
        }

      } else {
        print "$project\t$datasets\t$organism\tExpected $expected\tMissing Injector\n";
      }
    }
  }

  print "$project\t$datasets\t$organism\tExpected $expected\tNo Presenter Found\n" if($missingAttribution);
}

$sh->finish();

$dbh->disconnect();
