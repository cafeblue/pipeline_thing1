#!/bin/env perl
#Author: Lynette Lau
#Date: April 1, 2015 --> updated for v5.0 database structure
#Goes through the database and finds variants that are the same (position, alleles, and zygosity) and reports if the interpretation are different
use strict;
use warnings;
use lib './lib';
use Thing1::Common qw(:All);
use Carp qw(croak);

my $dbh = Common::connect_db($ARGV[0]);
my $config = Common::get_all_config($dbh);
my $variants_code = Common::get_encoding($dbh, "variants_sub");
my $interpre_code = Common::get_encoding($dbh, "interpretation");
my %interpretationHistory = map {$interpre_code->{'interpretation'}->{$_}->{'code'} => $_ } keys %{$interpre_code->{'interpretation'}};
my %variantType = map {$interpre_code->{'variantType'}->{$_}->{'code'} => $_ } keys %{$interpre_code->{'variantType'}};
my ($today, $yesterday) = Common::print_time_stamp();
my %zyg_decode = map { $variants_code->{'zygosity'}->{$_}->{'code'} => $_ } keys %{$variants_code->{'zygosity'}};

my %ignoreVar = (); #variants to ignore #key is chrom:gStart:ref:alt:zygosity
my $outputFile = $config->{'DISCORDANT_FOLDER'} . "discordant_intepretations." . $today . ".txt";
print "outputFile=$outputFile\n";
die "unable to create $outputFile\n" unless (open DISCORDFILE, '>' . $outputFile);

my %interVar = (); #key is chrom:start:end:allele:type:zygosity, value is the interprertation:postprocID separated by comma
my %sampleName = (); #key is the postprocID and the value is the sampleName;
my %interDate = ();  #key is interID and value is timestamp

###get all the discordant variants
my $getDiscordVar = "SELECT chrom, gStart, gEnd, ref, alt, zygosity FROM discordantVariants";
print "getDiscordVar=$getDiscordVar\n";
my $sthDV = $dbh->prepare($getDiscordVar) or die "Can't query database for discordant variants: ". $dbh->errstr() . "\n";
$sthDV->execute() or die "Can't execute query for discordant variants: " . $dbh->errstr() . "\n";
while (my @dataDV = $sthDV->fetchrow_array()) {
  my $chrom = "";
  my $zyg = "";
  my ($chromTmp, $gStart, $gEnd, $ref, $alt, $zygTmp) = @dataDV;

  if ($chromTmp eq "X") {
    $chrom = 24;
  } elsif ($chromTmp eq "Y") {
    $chrom = 25;
  } elsif ($chromTmp eq "MT" || $chromTmp eq "M") {
    $chrom = 26;
  } else {
    $chrom = $chromTmp;
  }

  $zyg = $variants_code->{'zygosity'}->{$zygTmp}->{'code'};

  my $key = $chrom . ":" . $gStart . ":" . $gEnd . ":" . $ref . ":" . $alt . ":" . $zyg;

  $ignoreVar{$key} = 0;
}

##go through interHistory and get the date of interpretation
my $getInterTime = "SELECT interID, time FROM interHistory";
#print STDERR "getInterTime=$getInterTime\n";
my $sthIT = $dbh->prepare($getInterTime) or die "Can't query database for interHistory info: ". $dbh->errstr() . "\n";
$sthIT->execute() or die "Can't execute query for interHistory info: " . $dbh->errstr() . "\n";

while (my @dataIT = $sthIT->fetchrow_array()) {
  my ($interID, $time) = @dataIT;
  if (defined $interDate{$interID}) {
    $interDate{$interID} = $interDate{$interID} . "|" . $time;
  } else {
    $interDate{$interID} = $time;
  }
}

# get the sampleID with the postprocess ID

my $getSampleN = "SELECT sampleID, postprocID, currentStatus FROM sampleInfo"; #no validation samples
print "getSampleN=$getSampleN\n";
my $sthSName = $dbh->prepare($getSampleN) or die "Can't query database for sample name info: ". $dbh->errstr() . "\n";
$sthSName->execute() or die "Can't execute query for sample name info: " . $dbh->errstr() . "\n";

while (my @dataN = $sthSName->fetchrow_array()) {
  my ($sampleID, $postprocID, $currentStatus) = @dataN;
  if (defined $sampleName{$postprocID}) {
    $sampleName{$postprocID} = $sampleName{$postprocID} . ";" . $sampleID . "|" . $currentStatus;
    print "$sampleID with ppID=$postprocID in the database twice?!\n";
  } else {
    $sampleName{$postprocID} = $sampleID . "|" . $currentStatus;
  }
}



# #get the exome coverage statistics from the databases for this sample
my $selectVariants = "SELECT interID, interpretation FROM interpretation WHERE interpretation != '0' AND interpretation !='1'";
#print STDERR "selectVariants=$selectVariants\n";
my $sthVar = $dbh->prepare($selectVariants) or die "Can't query database for interID info: ". $dbh->errstr() . "\n";
$sthVar->execute() or die "Can't execute query for interID info: " . $dbh->errstr() . "\n";

while (my @dataS = $sthVar->fetchrow_array()) {
  my ($interID, $interpret)  = @dataS;
  my $getInfo = "SELECT postprocID, chrom, genomicStart, genomicEnd, variantType, zygosity, refAllele, altAllele, cDNA, aaChange, geneSymbol, effect FROM variants_sub WHERE interID = '" . $interID . "'";

  #print STDERR "getInfo=$getInfo\n";
  my $sthInfo = $dbh->prepare($getInfo) or die "Can't query database for interID info: ". $dbh->errstr() . "\n";
  $sthInfo->execute() or die "Can't execute query for interID info: " . $dbh->errstr() . "\n";

  while (my @dataI = $sthInfo->fetchrow_array()) {
    #make a join from postprocID to sampleID
    print "dataI=@dataI\n";
    my ($postprocID, $chr, $gStart, $gEnd, $vType, $zyg, $ref, $alt, $cDNA, $aaChange, $geneSym, $effect) = @dataI;

    if ($effect != 29) {        ###ignore all synonymous variants
      my $inIgnore = 0;
      foreach my $ignore (keys %ignoreVar) {
        my @splitDot = split(/\:/,$ignore);
        print "ignore=$ignore\n";
        my ($iChrom, $iStart, $iEnd, $iRef, $iAlt, $iZyg) = @splitDot;
        if (($iChrom eq $chr) && ($iStart eq $gStart) && ($iEnd eq $gEnd) && ($iRef eq $ref) && ($iAlt eq $alt) && ($iZyg eq $zyg)) {
          $inIgnore = 1;
          print "ignore=$ignore!\n";
          last;
        }
      }
      if ($inIgnore == 0) {
        my $key = "$chr:$gStart:$gEnd:$ref:$alt:$vType:$zyg:$cDNA:$aaChange:$geneSym";
        my $val = "$interpret:$postprocID:$interID";

        print "added into interVar\n";
        if (defined $interVar{$key}) {
          $interVar{$key} = $interVar{$key} . "," . $val;
        } else {
          $interVar{$key} = $val;
        }
      }
    }
  }
}

$dbh->disconnect;

print DISCORDFILE "Chrom\tStart\tEnd\tRef\tAlt\tVariant Type\tZygosity\tGene\tcDNA\taaChange\tInterpretations\n";

foreach my $variant (keys %interVar) {
  my @splitD = split(/\:/,$variant);
  my ($chrom, $start, $end, $ref, $alt, $type, $zyg, $cDNA, $aaChange, $geneSym) = @splitD;
  my @splitC = split(/\,/,$interVar{$variant});

  my $same = "Y";
  my $oldInter = "";
  foreach my $interp (@splitC) {
    my @splitDots = split(/\:/,$interp);
    my ($interpret, $postprocID)  = @splitDots;
    if ($interpret != 0) {
      if ($oldInter eq "") {
        $oldInter = $interpret;
      } else {

        if ($oldInter != $interpret) {
          if (($oldInter == 5 && $interpret == 6) || ($oldInter == 6 && $interpret == 5)) {
            ##ignore treat benign == likely benign
          } else {

            $same = "N";
          }
        }
      }
    }

  }

  if ($same eq "N") {

    print DISCORDFILE "$chrom\t$start\t$end\t$ref\t$alt\t$variantType{$type}\t$zyg_decode{$zyg}\t$geneSym\t$cDNA\t$aaChange\t";
    foreach my $interp (@splitC) {
      my @splitDots = split(/\:/,$interp);
      my ($interpret, $postprocID, $interID) = @splitDots; 
      my $sampleInfo = $sampleName{$postprocID};
      if (defined $sampleInfo) {
        my @splitSemiColon = split(/\;/,$sampleInfo);
        foreach my $sampleI (@splitSemiColon) {
          my @splitLine = split(/\|/,$sampleI);
          my ($sN, $currentStatus) = @splitLine;
          if ($currentStatus != 12 ) { # don't report out validation samples
            my $time = $interDate{$interID};
            my $stringInter = $interpretationHistory{$interpret};
            print DISCORDFILE "$sN|$stringInter|$today|$interID|$postprocID";
            print DISCORDFILE "\t";
          }
        }
      } else {
        print "no postprocID = $postprocID found\n";
      }
    }
    print DISCORDFILE "\n";
  }
}

close(DISCORDFILE);

#my $sender = Mail::Sender->new();
#my $recipients= 'lynette.lau@sickkids.ca';
my $sender = new Mail::Sender {smtp => 'localhost'};
if ($sender->OpenMultipart({from => 'notice@thing1.sickkids.ca', to => $config->{'EMAIL_COORDINATORS'},
                            subject => "Discordant Interpretations $today",
                            boundary => 'boundary-test-1',
                            type => 'multipart/related'}) > 0) {
  $sender->Body({msg     => "Hi all,\n\nAttached is the Discordant Interpretation Report for $today.\n\nDo not reply to this email, Thing1 cannot read emails. If there are any issues please email lynette.lau\@sickkids.ca or weiw.wang\@sickkids.ca\n\nThanks,\nThing1 v5.0"
                });
  $sender->Attach({description => "discordant_interpretations.$today",
                   ctype => 'text/plain; charset=utf-8',
                   encoding => 'base64',
                   disposition => 'attachment',
                   file => "$outputFile"
                  });
  $sender->Close() or die "Close failed! $Mail::Sender::Error\n";
} else {
  die "Cannot send mail: $Mail::Sender::Error\n";
}
