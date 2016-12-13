#!/usr/bin/perl
#Recommended pragmas
use strict;
use warnings;
use diagnostics;


use Modern::Perl;
use CGI qw ( -utf8 );
use C4::Koha;
use C4::Auth;
use C4::Context;
use C4::Output;
use Koha::Patrons;
use Koha::Items;
use Koha::Libraries;
use Koha::LibraryCategories;


#use POSIX;
#use C4::Templates;
#use C4::Languages qw(getAllLanguages getTranslatedLanguages);
#use C4::Installer;
#use Koha;

#Setting variables
my $input    = new CGI;
my $query    = new CGI;
my $step     = $query->param('step');

my ( $template, $loggedinuser, $cookie) = get_template_and_user(
     {
        template_name => "/onboarding/onboardingstep" . ( $step ? $step : 1 ) . ".tt",
        query         => $query,
        type          => "intranet",
        authnotrequired => 0,
        debug           => 1,
    }
);

#Check database connection
my %info;
$info{'dbname'} = C4::Context->config("database");
$info{'dbms'} =
(   C4::Context->config("db_scheme")
    ? C4::Context->config("db_scheme")
     : "mysql" );

$info{'hostname'} = C4::Context->config("hostname");
$info{'port'}     = C4::Context->config("port");
$info{'user'}     = C4::Context->config("user");
$info{'password'} = C4::Context->config("pass");
my $dbh = DBI->connect(
         "DBI:$info{dbms}:dbname=$info{dbname};host=$info{hostname}"
          . ( $info{port} ? ";port=$info{port}" : "" ),
           $info{'user'}, $info{'password'}
);



#Performing each step of the onboarding tool
if ( $step && $step == 1 ) {
#This is the Initial step of the onboarding tool to create a library 


    my $createlibrary = $query->param('createlibrary');
    $template->param('createlibrary'=>$createlibrary);

#store inputted parameters in variables
    my $branchcode       = $input->param('branchcode');
    my $categorycode     = $input->param('categorycode');
    my $op               = $input->param('op') || 'list';
    my @messages;
    my $library;

#Find branchcode if it exists
    if ( $op eq 'add_form' ) {
        if ($branchcode) {
            $library = Koha::Libraries->find($branchcode);
         }

        $template->param(
            library    => $library,
            categories => [ Koha::LibraryCategories->search( {}, { order_by => [ 'categorytype', 'categoryname' ] } ) ],
            $library ? ( selected_categorycodes => [ map { $_->categorycode } $library->get_categories ] ) : (),
        );
    } elsif ( $op eq 'add_validate' ) {
        my @fields = qw(
            branchname
        );

        my $is_a_modif = $input->param('is_a_modif');

        my @categories;
        for my $category ( Koha::LibraryCategories->search ) {
            push @categories, $category
                if $input->param( "selected_categorycode_" . $category->categorycode );
         }
        if ($is_a_modif) {
            my $library = Koha::Libraries->find($branchcode);
            for my $field (@fields) {
                 $library->$field( scalar $input->param($field) );
            }
            $library->update_categories( \@categories );

            eval { $library->store; };

            if ($@) {
                push @messages, { type => 'alert', code => 'error_on_update' };
            } else {
                push @messages, { type => 'message', code => 'success_on_update' };
            }
        } else {
            $branchcode =~ s|\s||g;
            my $library = Koha::Library->new(
                 {   branchcode => $branchcode,
                    ( map { $_ => scalar $input->param($_) || undef } @fields )
                }
            );
            eval { $library->store; };
            $library->add_to_categories( \@categories );
            if ($@) {
                push @messages, { type => 'alert', code => 'error_on_insert' };
            } else {
                push @messages, { type => 'message', code => 'success_on_insert' };
            }
        }
            $op = 'list';
    }

        
}


output_html_with_http_headers $input, $cookie, $template->output;








