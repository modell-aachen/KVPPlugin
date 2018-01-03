#!/usr/bin/perl
# Converter that adds the column "Displayed Tab" to the given Workflow Document:
# 
# Please provide as parameter, which Workflow file you want to update
#  ./update_workflow_displayedTab.pl /var/www/qwikis/qwiki/data/_apps/Processes/DocumentApprovalWorkflow.txt 
#
# This script does not proof, if the column is already existing.
# No backups are made; that's your job.

# Copyright 2016 Modell Aachen GmbH
# License: GPLv2+

use strict;
use warnings;

# Set library paths in @INC, at compile time
BEGIN {
  if (-e './setlib.cfg') {
    unshift @INC, '.';
  } elsif (-e '../bin/setlib.cfg') {
    unshift @INC, '../bin';
  }
  require 'setlib.cfg';
}

use Data::GUID;
use Foswiki ();

my $filename;
my $found = 0;
my $table = '';
my $columnName;
my $inTable;
my $dry = 1;
my $regExp;

foreach(@ARGV){
  my $ARG = $_;
  if($ARG =~ m/^table=(.*)/){
    $table = $1 if $1 ne '';
  }elsif($ARG =~ m/^filename=(.*)/){
    $filename = $1 if $1 ne '';
  }elsif($ARG =~ m/^nodry=(.*)/){
    $dry = 0 if $1;
  }elsif($ARG =~ m/^col=(.*)/){
    $columnName = $1 if $1 ne '';
  }
}

unless(@ARGV && $table && $columnName && $filename){
    _printHelp();
}

if($table eq 'states'){
    $regExp = q(^\s*\|([\s*]*State[\s*]*\|[\s*]*Allow\s*Edit[\s*]*\|.*)\|\s*$);
}elsif($table eq 'transitions'){
    $regExp = q(^\s*\|([\s*]*State[\s*]*\|[\s*]*Action[\s*]*\|.*)\|\s*$);
}elsif($table eq 'default'){
    $regExp = q(^\s*\|([\s*]*State type[\s*]*)\|\s*$);
}else{
    print "TABLE-param is incorrect \n";
    _printHelp();
}

sub _printHelp{
  print "Remove column from one WorkflowTable\n";
  print "\t- nodry={0|1} default 0, set to 1 if you want to save all changes, by default nothing is saved\n";
  print "\t- table={default,states,transitions} this argument is mandatory. no default value \n";
  print "\t- filename={WorkflowFilename like DocumentApprovalWorkflow.txt} this argument is mandatory. no default value\n";
  print "\t- col={ColumnName like *DisplayNameDE*} this argument is mandatory. no default value\n";
  exit;
}

sub convert {
    print "DRY: filename:$filename columnName:$columnName table:$table \n" if $dry;
    my ($filename) = @_;
    open(my $tfh, '<:utf8', $filename) or warn("Can't open $filename: $!") && return;
    local $/;
    my $text = <$tfh>;
    close($tfh);
    my $origText = $text;
    $text = _removeColumn($text,_getCoulmnIndex($text, $columnName));
    print "DRY: $text" if $dry;
    if($found){
        print "Found Column: $columnName \n";
        unless($dry){
            print "NoDry: Write it back into file";
            open($tfh, '>:utf8', $filename) or warn("Can't open $filename for writing: $!") && return;
            print $tfh $text;
            close($tfh);
        }
    }else{
        print "Did not find Column: $columnName. Do not write File...\n";
    }
}

sub _getCoulmnIndex {
    my ($text, $columnName) = @_;
    foreach my $line ( split( /\n/, $text ) ) {
        if ($line =~ s/$regExp/$1/ix){
            # State table header
            my $i = 1;
            foreach my $col ( split( /\s*\|\s*/, $line ) ) {
                $col =~ s/^\s+|\s+$//g;
                if($col eq $columnName){
                    $found = 1;
                    return $i;
                } else{
                    $i++;
                }
            }
        }

    }
    
}

sub _removeColumn {
    my ($text,$columnIndex) = @_;
    my $newText = "";

    foreach my $line ( split( /\n/, $text ) ) {
        if ($line =~ s/$regExp/$1/ix){
            my $i = 0;
            foreach my $col ( split( /\s*\|\s*/, $line ) ) {
                $i++;
                next if($i eq $columnIndex);
                $newText = $newText . " | " . $col;
            }
            $newText = $newText . " |\n";
            $inTable = 'STATE';
        } elsif ( defined($inTable) && $line =~ s/^\s*\|\s*(.*?)\s*\|\s*$/$1/ ) {
            if ($inTable eq 'STATE'){
                my $i = 0;
                foreach my $col ( split( /\s*\|\s*/, $line ) ) {
                    $i++;
                    next if($i eq $columnIndex);
                    $newText = $newText . " | " . $col;
                }
                $newText = $newText . " |\n";
            }
        } else {
            $newText = $newText . $line . "\n";
            undef $inTable;
        }
    }
    return $newText;
}

convert($filename);

print "\nDone.\n";

1;
