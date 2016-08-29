#!/usr/bin/perl -w
#Author: Lynette Lau
#Date: April 1, 2015 --> updated for v5.0 database structure
#Goes through the database and finds variants that are the same (position, alleles, and zygosity) and reports if the interpretation are different

use strict;

use DBI;
use Time::localtime;
use Time::ParseDate;
use Time::Piece;
use Mail::Sender;
use File::stat;

#read in from a config file
my $configFile = "/localhd/data/db_config_files/pipeline_thing1_config/config_file_v5_test.txt";
my ($host,$port,$user,$pass,$db,$discordantDir,$ignoreFileName) = &read_in_config($configFile);

my %ignoreVar = (); #variants to ignore #key is chrom:gStart:ref:alt:zygosity
###read them in from the database


##read in the email address
my $email_lst_ref = &email_list("/home/pipeline/pipeline_thing1_config/email_list.txt");
my ($today, $yesterday) = &print_time_stamp();

my $outputFile = $discordantDir . "discordant_intepretations." . $today . ".txt";

print "outputFile=$outputFile\n";
unless (open DISCORDFILE, '>' . $outputFile) {
  die "unable to create $outputFile\n";
}

my %interVar = (); #key is chrom:start:end:allele:type:zygosity, value is the interprertation:postprocID separated by comma
my %sampleName = (); #key is the postprocID and the value is the sampleName;
my %interDate = ();  #key is interID and value is timestamp
#perl module to connect to database
my $dbh = DBI->connect("DBI:mysql:$db;mysql_local_infile=1;host=$host;port=$port",
                       $user, $pass, { RaiseError => 1 } ) or die ( "Couldn't connect to database: " . DBI->errstr );

###get all the discordant variants
my $getDiscordVar = "SELECT chrom, gStart, gEnd, ref, alt, zygosity FROM discordantVariants";
print "getDiscordVar=$getDiscordVar\n";
my $sthDV = $dbh->prepare($getDiscordVar) or die "Can't query database for discordant variants: ". $dbh->errstr() . "\n";
$sthDV->execute() or die "Can't execute query for discordant variants: " . $dbh->errstr() . "\n";
my @dataDV = ();
while (@dataDV = $sthDV->fetchrow_array()) {
  my $chrom = "";
  my $zyg = "";
  my $chromTmp = $dataDV[0];
  my $gStart = $dataDV[1];
  my $gEnd = $dataDV[2];
  my $ref = $dataDV[3];
  my $alt = $dataDV[4];
  my $zygTmp = $dataDV[5];

  if ($chromTmp eq "X") {
    $chrom = 24;
  } elsif ($chromTmp eq "Y") {
    $chrom = 25;
  } elsif ($chromTmp eq "MT" || $chromTmp eq "M") {
    $chrom = 26;
  } else {
    $chrom = $chromTmp;
  }

  if ($zygTmp eq "het") {
    $zyg = 1;
  } elsif ($zygTmp eq "hom") {
    $zyg = 2;
  } elsif ($zygTmp eq "het-alt") {
    $zyg = 3;
  } else {
    print "zygosity=$zygTmp has no known encoding\n";
  }

  my $key = $chrom . ":" . $gStart . ":" . $gEnd . ":" . $ref . ":" . $alt . ":" . $zyg;

  $ignoreVar{$key} = 0;
}

##go through interHistory and get the date of interpretation
my $getInterTime = "SELECT interID, time FROM interHistory";
#print STDERR "getInterTime=$getInterTime\n";
my $sthIT = $dbh->prepare($getInterTime) or die "Can't query database for interHistory info: ". $dbh->errstr() . "\n";
$sthIT->execute() or die "Can't execute query for interHistory info: " . $dbh->errstr() . "\n";

my @dataIT = ();
while (@dataIT = $sthIT->fetchrow_array()) {

  my $interID = $dataIT[0];
  my $time = $dataIT[1];
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

my @dataN = ();
while (@dataN = $sthSName->fetchrow_array()) {
  my $sampleID = $dataN[0];
  my $postprocID = $dataN[1];
  my $currentStatus = $dataN[2];
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

my @dataS = ();
while (@dataS = $sthVar->fetchrow_array()) {
  #get the genomic location, alleles of the interID
  my $interID = $dataS[0];
  my $interpret = $dataS[1];
  my $getInfo = "SELECT postprocID, chrom, genomicStart, genomicEnd, variantType, zygosity, refAllele, altAllele, cDNA, aaChange, geneSymbol, effect FROM variants_sub WHERE interID = '" . $interID . "'";

  #print STDERR "getInfo=$getInfo\n";
  my $sthInfo = $dbh->prepare($getInfo) or die "Can't query database for interID info: ". $dbh->errstr() . "\n";
  $sthInfo->execute() or die "Can't execute query for interID info: " . $dbh->errstr() . "\n";

  my @dataI = ();
  while (@dataI = $sthInfo->fetchrow_array()) {
    #make a join from postprocID to sampleID
    print "dataI=@dataI\n";
    my $postprocID = $dataI[0];
    my $chr = $dataI[1];
    my $gStart = $dataI[2];
    my $gEnd = $dataI[3];
    my $vType = $dataI[4];
    my $zyg = $dataI[5];
    my $ref = $dataI[6];
    my $alt = $dataI[7];
    my $cDNA = $dataI[8];
    my $aaChange = $dataI[9];
    my $geneSym = $dataI[10];
    my $effect = $dataI[11];

    if ($effect != 29) {        ###ignore all synonymous variants
      my $inIgnore = 0;
      foreach my $ignore (keys %ignoreVar) {
        my @splitDot = split(/\:/,$ignore);
        print "ignore=$ignore\n";
        my $iChrom = $splitDot[0];
        my $iStart = $splitDot[1];
        my $iEnd = $splitDot[2];
        my $iRef = $splitDot[3];
        my $iAlt = $splitDot[4];
        my $iZyg = $splitDot[5];
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
  my $chrom = $splitD[0];
  my $start = $splitD[1];
  my $end = $splitD[2];
  my $ref = $splitD[3];
  my $alt = $splitD[4];
  my $type = $splitD[5];
  my $zyg = $splitD[6];
  my $cDNA = $splitD[7];
  my $aaChange = $splitD[8];
  my $geneSym = $splitD[9];

  my @splitC = split(/\,/,$interVar{$variant});

  my $same = "Y";
  my $oldInter = "";
  foreach my $interp (@splitC) {
    my @splitDots = split(/\:/,$interp);
    my $interpret = $splitDots[0];
    my $postprocID = $splitDots[1];
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

    my $stringtype = "";
    my $stringzyg = "";
    if ($type == 1) {
      $stringtype = "indel";
    } elsif ($type == 2) {
      $stringtype = "indel";
    } elsif ($type == 3) {
      $stringtype = "snp";
    } elsif ($type == 4) {
      $stringtype = "mnp";
    } elsif ($type == 5) {
      $stringtype = "mixed";
    } else {
      $stringtype = "other";
    }

    if ($zyg == 1) {
      $stringzyg = "het";
    } elsif ($zyg == 2) {
      $stringzyg = "hom";
    } elsif ($zyg == 3) {
      $stringzyg = "het-alt";
    } else {
      $stringzyg = "other";
    }


    print DISCORDFILE "$chrom\t$start\t$end\t$ref\t$alt\t$stringtype\t$stringzyg\t$geneSym\t$cDNA\t$aaChange\t";
    foreach my $interp (@splitC) {
      my @splitDots = split(/\:/,$interp);
      my $interpret = $splitDots[0];
      my $postprocID = $splitDots[1];
      my $interID = $splitDots[2];


      #my $sN = $sampleName{$postprocID};
      my $sampleInfo = $sampleName{$postprocID};
      if (defined $sampleInfo) {
        my @splitSemiColon = split(/\;/,$sampleInfo);
        foreach my $sampleI (@splitSemiColon) {
          my @splitLine = split(/\|/,$sampleI);

          my $sN = $splitLine[0];
          my $currentStatus = $splitLine[1];
          if ($currentStatus != 12 ) { # don't report out validation samples
            my $time = $interDate{$interID};
            my $stringInter = "";
            if ($interpret == 2) {
              $stringInter = "pathogenic";
            } elsif ($interpret == 3) {
              $stringInter = "likely pathogenic";
            } elsif ($interpret == 4) {
              $stringInter = "VUS";
            } elsif ($interpret == 5) {
              $stringInter = "likely benign";
            } elsif ($interpret == 6) {
              $stringInter = "benign";
            } elsif ($interpret == 7) {
              $stringInter = "unknown";
            }
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
my $recipients = $email_lst_ref->{'WARNINGS'};
my $sender = new Mail::Sender {smtp => 'localhost'};
if ($sender->OpenMultipart({from => 'notice@thing1.sickkids.ca', to => $recipients,
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

sub print_time_stamp {
  my $retval = time();
  my $yetval = $retval - 86400;
  $yetval = localtime($yetval);
  my $localTime = localtime( $retval );
  my $time = Time::Piece->strptime($localTime, '%a %b %d %H:%M:%S %Y');
  my $timestamp = $time->strftime('%Y-%m-%d %H:%M:%S');
  print "\n\n_/ _/ _/ _/ _/ _/ _/ _/\n  ",$timestamp,"\n_/ _/ _/ _/ _/ _/ _/ _/\n";
  print STDERR "\n\n_/ _/ _/ _/ _/ _/ _/ _/\n  ",$timestamp,"\n_/ _/ _/ _/ _/ _/ _/ _/\n";
  return ($localTime->strftime('%Y%m%d'), $yetval->strftime('%Y%m%d'));
}

sub read_in_config {
  #read in the pipeline configure file
  #this filename will be passed from thing1 (from the database in the future)
  my ($configFile) = @_;
  my $data = "";
  my ($hosttmp,$porttmp,$usertmp,$passtmp,$dbtmp,$discordantTmp,$ignoreTmp);
  my $msgtmp = "";
  open (FILE, "< $configFile") or die "Can't open $configFile for read: $!\n";
  while ($data=<FILE>) {
    chomp $data;
    my @splitTab = split(/ /,$data);
    my $type = $splitTab[0];
    my $value = $splitTab[1];
    if ($type eq "HOST") {
      $hosttmp = $value;
    } elsif ($type eq "PORT") {
      $porttmp = $value;
    } elsif ($type eq "USER") {
      $usertmp = $value;
    } elsif ($type eq "PASSWORD") {
      $passtmp = $value;
    } elsif ($type eq "db") {
      $dbtmp = $value;
    } elsif ($type eq "DISCORDANTFOLDER") {
      $discordantTmp = $value;
    } elsif ($type eq "DISCORDANTIGNORE") {
      $ignoreTmp = $value;
    }

  }
  close(FILE);
  return ($hosttmp,$porttmp,$usertmp,$passtmp,$dbtmp,$discordantTmp,$ignoreTmp);
}


sub email_list {
  my $infile = shift;
  my %email;
  open (INF, "$infile") or die $!;
  while (<INF>) {
    chomp;
    my ($type, $lst) = split(/\t/);
    $email{$type} = $lst;
  }
  return(\%email);
}
