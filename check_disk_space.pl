#! /usr/bin/env perl
use strict;
use Time::localtime;
use Time::ParseDate;
use Time::Piece;
use Mail::Sender;

my $sub_status = 1;
my ($today, $yesterday) = &print_time_stamp();
$sub_status = &check_sequencer_connections();
$sub_status = &check_disk_space_on_thing1();
$sub_status = &check_disk_space_on_hpf();

## Check the connections to sequencers   #########
sub check_sequencer_connections {
    ## Check hiseq1  #
    my $errorMsg = "";
    my $pinglines = `ping 20.20.0.2 -c 4 -w 10 |tail -2 |head -1`;
    if ($pinglines !~ /4 packets transmitted, 4 received, 0% packet loss,/) {
        my $errorMsg .= "No connections to hiseq_1, please check the Network connections!\n";
    }
    else {
        my $nmap = `nmap 20.20.0.2 -PN -p 445 | grep open`;
        if ($nmap !~ /445\/tcp open  microsoft-ds/) {
            $errorMsg .= "Samba Connections to hiseq_1 failed! Please check the connections\n";
        }
    }
    
    ## Check hiseq2  #
    $pinglines = `ping 20.20.2.3 -c 4 -w 10 |tail -2 |head -1`;
    if ($pinglines !~ /4 packets transmitted, 4 received, 0% packet loss,/) {
        $errorMsg .= "No connections to hiseq_2, please check the Network connections!\n";
    }
    else {
        my $nmap = `nmap 20.20.2.3 -PN -p 445 | grep open`;
        if ($nmap !~ /445\/tcp open  microsoft-ds/) {
            $errorMsg .= "Samba Connections to hiseq_2 failed! Please check the connections\n";
        }
    }

    ## Check nextseq1 #
    $pinglines = `ping 20.20.4.2 -c 4 -w 10 |tail -2 |head -1`;
    if ($pinglines !~ /4 packets transmitted, 4 received, 0% packet loss,/) {
        $errorMsg .= "No connections to nextseq_1, please check the Network connections!\n";
    }
    else {
        my $nmap = `nmap 20.20.4.2 -PN -p 445 | grep open`;
        if ($nmap !~ /445\/tcp open  microsoft-ds/) {
            $errorMsg .= "Samba Connections to nextseq_1 failed! Please check the connections\n";
        }
    }

    ## Check nextseq2 #
    $pinglines = `ping 20.20.4.3 -c 4 -w 10 |tail -2 |head -1`;
    if ($pinglines !~ /4 packets transmitted, 4 received, 0% packet loss,/) {
        $errorMsg .= "No connections to nextseq_2, please check the Network connections!\n";
    }
    else {
        my $nmap = `nmap 20.20.4.3 -PN -p 445 | grep open`;
        if ($nmap !~ /445\/tcp open  microsoft-ds/) {
            $errorMsg .= "Samba Connections to nextseq_2 failed! Please check the connections\n";
        }
    }

    ## Check miseq1 #
    $pinglines = `ping 20.20.4.4 -c 4 -w 10 |tail -2 |head -1`;
    if ($pinglines !~ /4 packets transmitted, 4 received, 0% packet loss,/) {
        $errorMsg .= "No connections to miseq_1, please check the Network connections!\n";
    }
    else {
        my $nmap = `nmap 20.20.4.4 -PN -p 445 | grep open`;
        if ($nmap !~ /445\/tcp open  microsoft-ds/) {
            $errorMsg .= "Samba Connections to miseq_1 failed! Please check the connections\n";
        }
    }

    ## Check miseq2 #
    $pinglines = `ping 20.20.4.5 -c 4 -w 10 |tail -2 |head -1`;
    if ($pinglines !~ /4 packets transmitted, 4 received, 0% packet loss,/) {
        $errorMsg .= "No connections to miseq_2, please check the Network connections!\n";
    }
    else {
        my $nmap = `nmap 20.20.4.5 -PN -p 445 | grep open`;
        if ($nmap !~ /445\/tcp open  microsoft-ds/) {
            $errorMsg .= "Samba Connections to miseq_2 failed! Please check the connections\n";
        }
    }

    ## Check ls sequencer hiseq_1 folder  #
    $pinglines = `/home/wei.wang/apps/bin/check_job_time.sh 10 ls /localhd/data/sequencers/hiseq2500_1/flowcellA `;
    if ($pinglines =~ /command taking too long - killing/) {
       $errorMsg .= "Can't read the running folder of sequencer hiseq_1 \n";
    }

    ## Check ls sequencer hiseq_2 folder  #
    $pinglines = `/home/wei.wang/apps/bin/check_job_time.sh 10 ls /localhd/data/sequencers/hiseq2500_2/flowcellA `;
    if ($pinglines =~ /command taking too long - killing/) {
       $errorMsg .= "Can't read the running folder of sequencer hiseq_2 \n";
    }

    ## Check ls sequencer nextseq_1 folder  #
    $pinglines = `/home/wei.wang/apps/bin/check_job_time.sh 10 ls /localhd/data/sequencers/nextseq500_1/Illumina `;
    if ($pinglines =~ /command taking too long - killing/) {
       $errorMsg .= "Can't read the running folder of sequencer nextseq_1 \n";
    }

    ## Check ls sequencer nextseq_2 folder  #
    $pinglines = `/home/wei.wang/apps/bin/check_job_time.sh 10 ls /localhd/data/sequencers/nextseq500_1/Illumina `;
    if ($pinglines =~ /command taking too long - killing/) {
       $errorMsg .= "Can't read the running folder of sequencer nextseq_2 \n";
    }

    ## Check ls sequencer miseq_1 folder  #
    $pinglines = `/home/wei.wang/apps/bin/check_job_time.sh 10 ls /localhd/data/sequencers/miseqdx_1/Illumina `;
    if ($pinglines =~ /command taking too long - killing/) {
       $errorMsg .= "Can't read the running folder of sequencer miseq_1 \n";
    }

    ## Check ls sequencer miseq_2 folder  #
    $pinglines = `/home/wei.wang/apps/bin/check_job_time.sh 10 ls /localhd/data/sequencers/miseqdx_2/Illumina `;
    if ($pinglines =~ /command taking too long - killing/) {
       $errorMsg .= "Can't read the running folder of sequencer miseq_2 \n";
    }

    if ($errorMsg ne '') {
        email_error($errorMsg);
    }
    return 0;
}

sub check_disk_space_on_hpf {
    my $lastline = `ssh -i /home/wei.wang/.ssh/id_sra_thing1 wei.wang\@data1.ccm.sickkids.ca "df -h /hpf/largeprojects/pray/ |tail -1" 2>/dev/null`;
    my $percentage = (split(/\s+/, $lastline))[4];
    if ($percentage =~ /(\d+)\%/) {
        if ($1 >= 90) {
            my $errorMsg = "Warning!!!   Disk usage on HPF is greater than $1\% now, please delete the useless files\n\n $lastline";
            email_error($errorMsg);
        }
    }
    else {
        my $errorMsg = "Failed to get the percentage of the free space on HPF\n please run the df again on HPF\n";
        email_error($errorMsg);
    }
    return 0;
}

sub check_disk_space_on_thing1 {
    my $lastline = `df -h /localhd |tail -1 2>/dev/null`;
    my $percentage = (split(/\s+/, $lastline))[4];
    if ($percentage =~ /(\d+)\%/) {
        if ($1 >= 90) {
            my $errorMsg = "Warning!!!   Disk usage on thing1 is greater than $1\% now, please delete the useless files\n\n $lastline";
            email_error($errorMsg);
        }
    }
    else {
        my $errorMsg = "Failed to get the percentage of the free space on HPF\n please run the df again on HPF\n";
        email_error($errorMsg);
    }
    return 0;
}

sub email_error {
    my $errorMsg = shift;
    print STDERR $errorMsg;
    my $sampleID = shift;
    my $analysisID = shift;
    my $sender = Mail::Sender->new();
    my $mail   = {
        smtp                 => 'localhost',
        from                 => 'notice@thing1.sickkids.ca',
        to                   => 'lynette.lau@sickkids.ca, weiw.wang@sickkids.ca',
        subject              => "Job Status on HPF",
        ctype                => 'text/plain; charset=utf-8',
        skip_bad_recipients  => 1,
        msg                  => $errorMsg 
    };
    my $ret =  $sender->MailMsg($mail);
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

