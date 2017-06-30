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

my $filename = "$ARGV[0]"; 
my $inTable;
my @fields;
my $defaultCol;
my %default = ();

use Data::GUID;
use Foswiki ();

sub convert {
    my ($filename) = @_;
    open(my $tfh, '<:utf8', $filename) or warn("Can't open $filename: $!") && return;
    local $/;
    my $text = <$tfh>;
    close($tfh);
    my $origText = $text;
    $text = _addDisplayedTabColumn($text);
    return 1 if $text eq $origText;
    open($tfh, '>:utf8', $filename) or warn("Can't open $filename for writing: $!") && return;
    print $tfh $text;
    close($tfh);
    2;
}

sub _addDisplayedTabColumn {
    my ($text) = @_;
    my $newText = "";

    foreach my $line ( split( /\n/, $text ) ) {
        if ($line =~ s/^\s*\|([\s*]*State[\s*]*\|[\s*]*Allow\s*Edit[\s*]*\|.*)\|\s*$/$1/ix){
            # State table header
            @fields = map { _cleanField($_) } split( /\s*\|\s*/, $line );

            $newText = $newText . "|" . $line . " | *Displayed Tab* |" . "\n";
            $inTable = 'STATE';
        }
        elsif ( defined($inTable) && $line =~ s/^\s*\|\s*(.*?)\s*\|\s*$/$1/ ) {
            my %data;
            my $i = 0;
            if ($inTable eq 'STATE'){
                foreach my $col ( split( /\s*\|\s*/, $line ) ) {
                    $data{ $fields[ $i++ ] } = $col;
                }

                # If the actual line contains a known status, add displayed tab column
                if (index($data{state}, "CONTENT_REVIEW") != -1) {
                    $newText = $newText . "| " . $line . " | Content review |" . "\n";
                } elsif (index($data{state}, "FORMAL_REVIEW") != -1) {
                    $newText = $newText . "| " . $line . " | Formal review |" . "\n";
                } elsif (index($data{state}, "NEW") != -1) {
                    $newText = $newText . "| " . $line . " | Drafts & discussions |" . "\n";
                } elsif (index($data{state}, "DRAFT") != -1) {
                    $newText = $newText . "| " . $line . " | Drafts & discussions |" . "\n";
                } elsif (index($data{state}, "DISCUSSION") != -1) {
                    $newText = $newText . "| " . $line . " | Drafts & discussions |" . "\n";
                } elsif (index($data{state}, "APPROVED") != -1) {
                    $newText = $newText . "| " . $line . " | Approved pages |" . "\n";
                } else {
                    $newText = $newText . "| " . $line . "|\n";
                }
                
            }
        }
        else {
            $newText = $newText . $line . "\n";
            undef $inTable;
        }
    }
    return $newText;
}

sub _cleanField {
    my ($text) = @_;
    $text ||= '';
    $text = lc($text);
    $text =~ s/[^\w.]//gi;
    return $text;
}

convert($filename);


print STDERR "\nDone.\n";
