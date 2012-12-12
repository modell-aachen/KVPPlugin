# See bottom of file for license and copyright information
use strict;
use warnings;

package KVPPluginTests;

use FoswikiFnTestCase;
our @ISA = qw( FoswikiFnTestCase );

use strict;
use warnings;

use Foswiki();
use Error qw ( :try );
use Foswiki::Plugins::KVPPlugin();
use KVPPlugin::Helper qw ( :attachments :webs WRKFLW setup );

my $users;
my @attachments;

sub new {
    my ($class, @args) = @_;
    my $this = shift()->SUPER::new('KVPPluginTests', @args);
    return $this;
}

sub loadExtraConfig {
    my $this = shift;
    $this->SUPER::loadExtraConfig();
    $Foswiki::cfg{Plugins}{KVPPlugin}{Enabled} = 1;
}

# Set up the test fixture
sub set_up {
    my $this = shift;

    $this->SUPER::set_up();

    our $users = Helper::set_up_users($this);

    $this->{webs} = Helper::set_up_webs($this);

    @attachments = Helper::set_up_attachments($this);
}

sub tear_down {
    my $this = shift;

    Helper::tear_down_attachments(\@attachments);

    unless ( $ENV{KEEPTESTWEBS} ) {
        Helper::tear_down_webs( $this, $this->{webs} );
    }

    $this->SUPER::tear_down();
}

# Test if...
# ...a fork will apply the default suffix
# ...changing the default suffix creates a discussion with the new suffix
# ...the context 'KVPHasDiscussion' is set correctly
#
# Note: The default suffix must not be set to the default value (TALK) in configure.
sub test_suffixTests {
    my ( $this ) = @_;

    my $defaultSuffix = $Foswiki::cfg{Extensions}{KVPPlugin}{suffix};
    $this->assert_equals( 'TALK', $defaultSuffix, "Suffix has been changed form TALK to $defaultSuffix!" );

    my $user = Helper::becomeAnAdmin($this);

    my $web = Helper::KVPWEB;
    my $query = Unit::Request->new( { action=>'view', topic=>"$web.SuffixTest" } );

    # Fork with default-Suffix
    Helper::createWithState( $this, Helper::KVPWEB, 'SuffixTest', 'FREIGEGEBEN' );
    $this->createNewFoswikiSession( $user, $query );
    $this->assert( !Foswiki::Func::expandCommonVariables("%IF{\"context KVPHasDiscussion\" then=\"1\" else=\"0\"}%"), "test-topic SuffixTest already has a discussion!" );
    Helper::createDiscussion( $this, Helper::KVPWEB, 'SuffixTest' );
    $this->assert(Foswiki::Func::topicExists( Helper::KVPWEB, 'SuffixTestTALK' ), "Could not find discussion with default suffix!");
    $this->createNewFoswikiSession( $user, $query );
    $this->assert( Foswiki::Func::expandCommonVariables("%IF{\"context KVPHasDiscussion\" then=\"1\" else=\"0\"}%"), "Discussion with defaultsuffix does not set context!" );

    try {
        # Now fork with different suffix
        $Foswiki::cfg{Extensions}{KVPPlugin}{suffix} = 'AndNowForSomethingCompletelyDifferent';
        $this->createNewFoswikiSession( $user, $query );
        $this->assert( !Foswiki::Func::expandCommonVariables("%IF{\"context KVPHasDiscussion\" then=\"1\" else=\"0\"}%"), "Context still reports discussion with default-suffix altough suffix changed!" );
        Helper::createDiscussion( $this, Helper::KVPWEB, 'SuffixTest' );
        $this->assert(Foswiki::Func::topicExists( Helper::KVPWEB, 'SuffixTestAndNowForSomethingCompletelyDifferent' ), "Could not find discussion with changed suffix!");
        $this->createNewFoswikiSession( $user, $query );
        $this->assert( Foswiki::Func::expandCommonVariables("%IF{\"context KVPHasDiscussion\" then=\"1\" else=\"0\"}%"), "Context still does not report discussion with changed suffix!" );
    } finally {
        $Foswiki::cfg{Extensions}{KVPPlugin}{suffix} = $defaultSuffix;
    };
}

# Test if...
# ...the NEW transition is executed when creating a topic
# ...lack of a NEW transition inhibits creating topic for non-admins
# ...admins can still create topics, even if there is no NEW transition
# ...non-admins can create topics without NEW transition if allowed in configure
sub test_attributeNEW {
    my ( $this ) = @_;

    use constant TOPIC => 'TestTopicNEW';

    our $users;

    my $user = Helper::becomeAnAdmin($this);

    # with NEW transition
    Foswiki::Func::saveTopic( Helper::KVPWEB, TOPIC, undef, 'This should be a draft' );
    my $state = Foswiki::Func::expandCommonVariables("%WORKFLOWMETA%", TOPIC, Helper::KVPWEB );
    $this->assert_equals( 'ENTWURF', $state, 'Newly created topic did not do the NEW transition.' );

    # without NEW transition
    Foswiki::Func::saveTopic( Helper::NONEW, TOPIC, undef, 'This should be a new article' );
    $state = Foswiki::Func::expandCommonVariables("%WORKFLOWMETA%", TOPIC, Helper::NONEW );
    $this->assert_equals( 'NEU', $state, 'Newly created topic is not in first state.' );

    # check if nonadmins are beeing inhibited if there is no NEW transition
    my $query = Unit::Request->new( { action=>'view' } );
    $this->createNewFoswikiSession( $users->{test1}, $query );
    try {
        Foswiki::Func::saveTopic( Helper::NONEW, TOPIC."NotAllowed", undef, 'This shouldn\'t be possible' );
        $this->assert( 0, "Nonadmin could create an article although there was no NEW transition" );
    } catch Foswiki::OopsException with {
        my $e = shift;
        $this->assert( $e->{template} eq 'workflowerr' && $e->{def} eq 'topic_creation', "Wrong Exception on denied save." );
    }
    catch Error::Simple with {
        $this->assert( 0, shift->stringify() || '' );
    };
    # check if nonadmins are allowed if there is no NEW transition and force is disabled in configure
    try {
        $Foswiki::cfg{Plugins}{KVPPlugin}{NoNewRequired} = 1;
        $query = Unit::Request->new( { action=>'view' } );
        $this->createNewFoswikiSession( $users->{test1}, $query );
        Foswiki::Func::saveTopic( Helper::NONEW, TOPIC."NewNotForced" );
    } catch Foswiki::OopsException with {
        my $e = shift;
        $this->assert( 0, "Nonadmin could not create an article although NEW transition wasn't forced" );
    } catch Error::Simple with {
        $this->assert( 0, shift->stringify() || '' );
    } finally {
        $Foswiki::cfg{Plugins}{KVPPlugin}{NoNewRequired} = 0;
    };

    return;
}

1;
__END__
Foswiki - The Free and Open Source Wiki, http://foswiki.org/

Author: Modell Aachen GmbH

Copyright (C) 2008-2011 Foswiki Contributors. Foswiki Contributors
are listed in the AUTHORS file in the root of this distribution.
NOTE: Please extend that file, not this notice.

This program is free software; you can redistribute it and/or
modify it under the terms of the GNU General Public License
as published by the Free Software Foundation; either version 2
of the License, or (at your option) any later version. For
more details read LICENSE in the root of this distribution.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.

As per the GPL, removal of this notice is prohibited.
