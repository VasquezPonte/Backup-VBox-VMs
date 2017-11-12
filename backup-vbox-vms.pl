#!/usr/bin/perl -w
#============================================================================== #
# Program:      Backup VBox VMs                                                 #
# Description:  Script for backing up VirtualBox VMs from host file system      #
# Version:      1.0                                                             #
# File:         backup-vbox-vms.pl                                              #
# Author:       Vásquez Ponte, 2017 (https://vasquezponte.com/contact)          #
#============================================================================== #

use strict;
use warnings;
use File::Basename;
use Sysadm::Install qw(:all);
use POSIX;

# Constants
# -------------------------------------------------------------------------------
use constant BACKUP_PATH        => '/path/to/backup/folder';
use constant VBOXMANAGE         => '/usr/bin/VBoxManage';
use constant TAR                => '/bin/tar';
use constant CURRENT_DATE       => strftime("%Y-%m-%d", localtime);
use constant VMSTATE_RUNNING    => '"running"';
use constant VMSTATE_POWEROFF   => '"poweroff"';
use constant VMSTATE_HEADLESS   => '"headless"';

# Variables
# -------------------------------------------------------------------------------
my $force = 0;
my $help = 0;
my ($stdout, $stderr, $exit_code);
my ($vm_name, $vm_uuid, $vm_state, $vm_path, $vm_folder, $vm_session);
my $vms_href = {};
my @lines = ();
my ($line, $available, $filename);

# ============================================================================= #
# ===============================   Main   ==================================== #
# ============================================================================= #

if (defined $ARGV[0]) {
    if ($ARGV[0] eq '-f' || $ARGV[0] eq '-force') { $force = 1 }
    else { $help = 1 }
}
if ($help) {
        print "\n".
        'Usage: perl backup-vbox-vms.pl [option]'. "\n\n".
        'where options include:'. "\n".
        "\t". '-f -force'. "\t\t". 'shut down VMs before copying files'. "\n".
        "\t". '-? -help'. "\t\t". 'print this help message'. "\n".
        "\n";
        exit 0;
}

print "\n===\n= Start: ". (localtime) ."\n===\n\n";

# Check backup destination
check_backup_folder();

# Back up virtual machines
($stdout, $stderr, $exit_code) = tap VBOXMANAGE, 'list', 'vms';
if ($exit_code == 0) {
    @lines = split "\n", $stdout;
} else {
	die "$stderr\n";
}
foreach $line (@lines) {
	$line =~ s/^\s+|\s+$//g;
	next if ($line eq '');
	($vm_name, $vm_uuid) = ($line =~ /\"(.*?)\" \{(.*?)\}/);
	if ($vm_name ne '' && $vm_uuid ne '') {
		($vm_state, $vm_session, $vm_path, $vm_folder) = parse_vminfo($vm_uuid);
		$vms_href->{$vm_uuid}->{'name'} = $vm_name;
		$vms_href->{$vm_uuid}->{'state'} = $vm_state;
		$vms_href->{$vm_uuid}->{'session'} = $vm_session;vate
		$vms_href->{$vm_uuid}->{'path'} = $vm_path;
		$vms_href->{$vm_uuid}->{'folder'} = $vm_folder;
		$vms_href->{$vm_uuid}->{'changed'} = 0;
	}
}
foreach $vm_uuid (keys %$vms_href) {
	$available = 0;
	if ($force && $vms_href->{$vm_uuid}->{'state'} ne VMSTATE_POWEROFF) {
		print 'Shutting down "'. $vms_href->{$vm_uuid}->{'name'} .'" ... ';
		($stdout, $stderr, $exit_code) = tap VBOXMANAGE, 'controlvm', $vm_uuid, 'poweroff';
		if ($exit_code == 0) {
            $vms_href->{$vm_uuid}->{'changed'} = 1;
            $available = 1;
            print "done\n";
		} else {
		    print "\nError: Could not shut down the VM.\n";
		}
	}
	if ($available || $vms_href->{$vm_uuid}->{'state'} eq VMSTATE_POWEROFF) {
		$filename = BACKUP_PATH .'/'. CURRENT_DATE .'_'. $vms_href->{$vm_uuid}->{'folder'} .'.tar.gz';
		print 'Backing up "'. $vms_href->{$vm_uuid}->{'name'} .'" ... ';
	    ($stdout, $stderr, $exit_code) = tap TAR, '-C', $vms_href->{$vm_uuid}->{'path'}, '-czhf', $filename, $vms_href->{$vm_uuid}->{'folder'};
	    if ($exit_code == 0) {
	        print "done\n";
	    } else {
	        print "\nError: Could not create file \"$filename\".\n";
	    }
	}
    if ($vms_href->{$vm_uuid}->{'changed'} && $vms_href->{$vm_uuid}->{'state'} eq VMSTATE_RUNNING) {
        print 'Starting "'. $vms_href->{$vm_uuid}->{'name'} .'" ... ';
        if ($vms_href->{$vm_uuid}->{'session'} eq VMSTATE_HEADLESS) {
        	($stdout, $stderr, $exit_code) = tap VBOXMANAGE, 'startvm', $vm_uuid, '--type', 'headless';
        } else {
        	($stdout, $stderr, $exit_code) = tap VBOXMANAGE, 'startvm', $vm_uuid;
        }
        if ($exit_code == 0) {
            print "done\n";
        } else {
            print "\nError: Could not start the VM.\n";
        }
    }
    print "\n";
}

print "===\n= End: ". (localtime) ."\n===\n\n";

# ============================================================================= #
# ===========================  Subroutines  =================================== #
# ============================================================================= #

#
# sub parse_vminfo ( string )
#
sub parse_vminfo {
    my $vm_uuid = shift;
    my ($stdout, $stderr, $exit_code);
    my ($vm_path, $vm_folder);
    my ($key, $value);
    my $href = {};
    my @lines = ();
    my $line;
    
    ($stdout, $stderr, $exit_code) = tap VBOXMANAGE, 'showvminfo', $vm_uuid, '--machinereadable';
    @lines = split "\n", $stdout;
	foreach $line (@lines) {
	    $line =~ s/^\s+|\s+$//g;
	    next if ($line eq '');
        ($key, $value) = split "=", $line;
        $href->{$key} = $value;
	}
	$href->{'CfgFile'} =~ s/\"//g;
	$vm_path = dirname($href->{'CfgFile'});
	$vm_folder = basename($vm_path);
	$vm_path = dirname($vm_path);
	
    return ($href->{'VMState'}, $href->{'SessionName'}, $vm_path, $vm_folder);
}

#
# sub writable_backup_folder ( string )
#
sub check_backup_folder {
	use File::Temp qw/ tempfile tempdir /;
	use Try::Tiny;
	
	print 'Checking backup folder "'. BACKUP_PATH .'" ... ';
	try {
		my ($fh, $filename) = tempfile(DIR => BACKUP_PATH, SUFFIX => '.tmp', UNLINK => 1);
		print "OK\n\n";
	} catch {
		print "\n" . 'Error: Backup folder "'. BACKUP_PATH .'" does not exist or is not writable.'. "\n";
		die "\n";
	}
}

