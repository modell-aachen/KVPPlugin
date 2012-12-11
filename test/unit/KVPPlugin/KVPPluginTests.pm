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
