#!/usr/bin/perl
#Recommended pragmas
use strict;
use warnings;
use diagnostics;


use Modern::Perl;

#External modules
use CGI qw ( -utf8 );
use List::MoreUtils qw/uniq/;
use Digest::MD5 qw(md5_base64);
use Encode qw( encode );

#Internal modules 
use C4::Koha;
use C4::Auth;
use C4::Context;
use C4::Output;
use C4::Members;
use C4::Members::Attributes;
use C4::Members::AttributeTypes;
use C4::Log;
use C4::Letters;
use C4::Form::MessagingPreferences; 
use Koha::AuthorisedValues;
use Koha::Patron::Debarments;
use Koha::Cities;
use Koha::Patrons;
use Koha::Items;
use Koha::Libraries;
use Koha::LibraryCategories;
use Koha::Database;
use Koha::DateUtils;
use Koha::Patron::Categories;
use Koha::Patron::HouseboundRole;
use Koha::Patron::HouseboundRoles;
use Koha::Token;
use Email::Valid;
use Module::Load;

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


#Create Patron category
}elsif ( $step && $step == 2 ){

    #Initialising values
    my $input         = new CGI;
    my $searchfield   = $input->param('description') // q||;
    my $categorycode  = $input->param('categorycode');
    my $op            = $input->param('op') // 'list';
    my @messages;

    my ( $template, $loggedinuser, $cookie ) = get_template_and_user(
    {
        template_name   => "/onboarding/onboardingstep2.tt",
        query           => $input,
        type            => "intranet",
        authnotrequired => 0,
        flagsrequired   => { parameters => 'parameters_remaining_permissions' },
        debug           => 1,
    }
    );
    #When the user first arrives on the page
    if ( $op eq 'add_form' ) {
        my $category;
        if ($categorycode) {
            $category          = Koha::Patron::Categories->find($categorycode);
        }

        $template->param(
            category => $category,
        );

        if ( C4::Context->preference('EnhancedMessagingPreferences') ) {
            C4::Form::MessagingPreferences::set_form_values(
                { categorycode => $categorycode }, $template );
        }
    }
    #Once the user submits the page, this code validates the input and adds it
    #to the database as a new patron category 
    elsif ( $op eq 'add_validate' ) {
        my $categorycode = $input->param('categorycode');
        my $description = $input->param('description');
        my $overduenoticerequired = $input->param('overduenoticerequired');
        my $category_type = $input->param('category_type');
        my $default_privacy = $input->param('default_privacy');
        my $enrolmentperiod = $input->param('enrolmentperiod');
        my $enrolmentperioddate = $input->param('enrolmentperioddate') || undef;

        #Converts the string into a date format
        if ( $enrolmentperioddate) {
            $enrolmentperioddate = output_pref(
                    {
                        dt         => dt_from_string($enrolmentperioddate),
                        dateformat => 'iso',
                        dateonly   => 1,
                    }
            );
        }
        #Adds to the database
        my $category = Koha::Patron::Category->new({
                categorycode=> $categorycode,
                description => $description,
                overduenoticerequired => $overduenoticerequired,
                category_type=> $category_type,
                default_privacy => $default_privacy,
                enrolmentperiod => $enrolmentperiod,
                enrolmentperioddate => $enrolmentperioddate,
        });
        eval {
            $category->store;
        };

        #Error messages 
        if($@){
            push @messages, {type=> 'error', code => 'error_on_insert'};
        }else{
            push @messages, {type=> 'message', code => 'success_on_insert'};
        }
    }
#Create a patron
}elsif ( $step && $step == 3 ){

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

        my $categories;
        $categories= Koha::Patron::Categories->search();
        $template->param(
                categories => $categories,
        );



    my $input = new CGI;
    my $op = $input->param('op');
    my @messages; 

    my ($template, $loggedinuser, $cookie)
        = get_template_and_user({
                template_name => "/onboarding/onboardingstep3.tt",
                query => $input,
                type => "intranet",
                authnotrequired => 0,
                flagsrequired => {borrowers => 1},
                debug => 1,
        });

    if($op eq 'add_form'){
        my $member;
        $template->param(
            member => $member,
        );


    }
    elsif($op eq 'add_validate'){
        my $surname => $input->param('surname');
        my $firstname => $input->param('firstname');
        my $cardnumber => $input->param('cardnumber');
        my $libraries => $input->param('libraries');
        my $categorycode_entry => $input->param('categorycode_entry');
        my $userid => $input->param('userid');
        my $password => $input->param('password');
        my $password2 =>$input->param('password2');

        my $member = Koha::Patron->new({
                surname => $surname,
                firstname => $firstname,
                cardnumber => $cardnumber,
                libraries => $libraries,
                categorycode_entry => $categorycode_entry,
                userid => $userid,
                password => $password,
                password2 => $password2,
        });
        eval {
            $member->store;
        };
         
        if($@){
            push @messages, {type=> 'error', code => 'error_on_insert'};
        }else{
            push @messages, {type=> 'message', code => 'success_on_insert'};
        }
 
    }


}elsif ( $step && $step == 4){

    my $createitemtype = $query->param('createitemtype');
    $template->param('createitemtype'=>$createitemtype);

}elsif ( $step && $step == 5){

    my $createcirculationrule = $query->param('createcirculationrule');
    $template->param('createcirculationrule'=>$createcirculationrule);


}







output_html_with_http_headers $input, $cookie, $template->output;

