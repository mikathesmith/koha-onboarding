#!/usr/bin/perl

# Copyright Pat Eyler 2003
# Copyright Biblibre 2006
# Parts Copyright Liblime 2008
# Parts Copyright Chris Nighswonger 2010
#
# This file is part of Koha.
#
# Koha is free software; you can redistribute it and/or modify it
# under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 3 of the License, or
# (at your option) any later version.
#
# Koha is distributed in the hope that it will be useful, but
# WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with Koha; if not, see <http://www.gnu.org/licenses>.

use Modern::Perl;

use CGI qw ( -utf8 );
use List::MoreUtils qw/ any /;
use LWP::Simple;
use XML::Simple;
use Config;

use C4::Output;
use C4::Auth;
use C4::Context;
use C4::Installer;

use Koha;
use Koha::Acquisition::Currencies;
use Koha::Patrons;
use Koha::Caches;
use Koha::Config::SysPrefs;
use C4::Members::Statistics;

#use Smart::Comments '####';

my $query = new CGI;
my ( $template, $loggedinuser, $cookie ) = get_template_and_user(
    {
        template_name   => "summary.tt",
        query           => $query,
        type            => "intranet",
        authnotrequired => 0,
        flagsrequired   => { catalogue => 1 },
        debug           => 1,
    }
);


output_html_with_http_headers $query, $cookie, $template->output;
