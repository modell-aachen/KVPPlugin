#!/usr/bin/perl -w
#
use strict;
use warnings;

BEGIN { unshift @INC, split( /:/, $ENV{FOSWIKI_LIBS} ); }
use Foswiki::Contrib::Build;

package KVPPluginBuild;
our @ISA = qw(Foswiki::Contrib::Build);

sub new {
  my $class = shift;
  return bless($class->SUPER::new( "KVPPlugin" ), $class);
}


sub target_release {
    my $this = shift;

    print <<GUNK;
Building release $this->{RELEASE} of $this->{project}, from version $this->{VERSION}
GUNK
    if ( $this->{-v} ) {
        print 'Package name will be ', $this->{project}, "\n";
        print 'Topic name will be ', $this->getTopicName(), "\n";
    }

    $this->_installDeps();

    $this->build('compress');
    $this->build('build');
    $this->build('installer');
    $this->build('stage');
    $this->build('archive');
}

sub _installDeps {
  my $this = shift;

  local $| = 1;
  print $this->sys_action( qw(yarn) );
  print $this->sys_action( qw(yarn build) );
  # note: on error BuildContrib will swallow up STDOUT, so we wouldn't see which tests failed
  print $this->sys_action( qw(yarn lint 1>&2) );
  print $this->sys_action( qw(yarn test:unit 1>&2) );
}

my $build = KVPPluginBuild->new();
$build->build( $build->{target} );
