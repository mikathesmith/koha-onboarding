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


#Setting variables
my $input    = new CGI;
my $query    = new CGI;
my $step     = $query->param('step');

#Getting the appropriate template to display to the user-->
my ( $template, $loggedinuser, $cookie) = get_template_and_user(
     {
        template_name => "/onboarding/onboardingstep" . ( $step ? $step : 0 ) . ".tt",
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


#Store the value of the input name='op' from the template in the variable $op
my $op = $query->param('op');
$template->param('op'=>$op);
if ( $op && $op eq 'finish' ) { #If the value of $op is equal to 'finish' then redirect to /cgi-bin/koha/mainpage.pl
    print $query->redirect("/cgi-bin/koha/mainpage.pl");
    exit;
}

my $start = $query->param('start');
$template->param('start'=>$start);

if ( $start && $start eq 'Start setting up my Koha' ){
    my $libraries = Koha::Libraries->search( {}, { order_by => ['branchcode'] }, );
    $template->param(libraries   => $libraries,
              group_types => [
                {   categorytype => 'searchdomain',
                    categories   => [ Koha::LibraryCategories->search( { categorytype => 'searchdomain' } ) ],
                },
                {   categorytype => 'properties',
                         categories   => [ Koha::LibraryCategories->search( { categorytype => 'properties' } ) ],
                },
              ]
    );

#Check if the input name=step is equal to 1 i.e. if the user has clicked the 'submit' button on the 'Create a library' screen 1 of the onboarding tool
}elsif ( $step && $step == 1 ) {

    my $createlibrary = $query->param('createlibrary'); #Store the inputted library branch code and name in $createlibrary
    $template->param('createlibrary'=>$createlibrary); # Hand the $createlibrary values back to the template

#store inputted parameters in variables
    my $branchcode       = $input->param('branchcode');
    my $categorycode     = $input->param('categorycode');
    my $op               = $input->param('op') || 'list';
    my @messages;
    my $library;

    if ( $op eq 'add_validate' ) {# Check if the form that the user has submitted is form name='add_validate'

           my @fields = qw(
                branchname
            ); #Take the text 'branchname' and store it in the @fields array

            $branchcode =~ s|\s||g; # Use a regular expression to check the value of th inputtedd branchcode 
            my $library = Koha::Library->new(
                {   branchcode => $branchcode, 
                    ( map { $_ => scalar $input->param($_) || undef } @fields )
                }
            ); #Create a new library object and store the branchcode and @fields array values in this new library object
            eval { $library->store; }; #Use the eval{} function to store the library object

            if ($@) {
                push @messages, { type => 'alert', code => 'error_on_insert' };
            } else {
                push @messages, { type => 'message', code => 'success_on_insert' };
            } # If there are values in the $@ then push the values type => 'alert', code => 'error_on_insert' into the @messages array else push the values type => 'message', code => 'success_on_insert' to that array
        }

}elsif ( $step && $step == 2 ){

    my $createpatroncategory = $query->param('createpatroncategory');
    $template->param('createpatroncategory'=>$createpatroncategory);

}elsif ( $step && $step == 3 ){

    my $createpatron = $query->param('createpatron');
    $template->param('createpatron'=>$createpatron);

}elsif ( $step && $step == 4){

    my $createitemtype = $query->param('createitemtype');
    $template->param('createitemtype'=>$createitemtype);

}elsif ( $step && $step == 5){

    my $createcirculationrule = $query->param('createcirculationrule');
    $template->param('createcirculationrule'=>$createcirculationrule);


}







output_html_with_http_headers $input, $cookie, $template->output;









