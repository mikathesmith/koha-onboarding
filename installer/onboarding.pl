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
use Koha::ItemTypes;
use Koha::Patron::HouseboundRole;
use Koha::Patron::HouseboundRoles;
use Koha::Token;
use Email::Valid;
use Module::Load;

#Imports for item types step 4
use Koha::ItemTypes;
use Koha::Localizations;

#Imports for circulation rule step 5
use Koha::IssuingRule;
use Koha::IssuingRules;
use Koha::Logger;
use Koha::RefundLostItemFeeRule;
use Koha::RefundLostItemFeeRules;

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


#Store the value of the template input name='op' in the variable $op so we can check if the user has pressed the button with the name="op" and value="finish" meaning the user has finished the onboarding tool.
my $op = $query->param('op');
$template->param('op'=>$op);
if ( $op && $op eq 'finish' ) { #If the value of $op equals 'finish' then redirect user to /cgi-bin/koha/mainpage.pl
    print $query->redirect("/cgi-bin/koha/mainpage.pl");
    exit;
}


#Store the value of the template input name='start' in the variable $start so we can check if the user has pressed this button and starting the onboarding tool process
my $start = $query->param('start');
$template->param('start'=>$start); #Hand the start variable back to the template
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


#Select any library records from the database and hand them back to the template in the libraries variable. 
}elsif (  $start && $start eq 'Add a patron category' ){

#Select all the patron category records in the categories database table and store them in the newly declared variable $categories
    my $categories = Koha::Patron::Categories->search(); 
    $template->param(
        categories => $categories,
    ); #Hand the variable categories back to the template

}elsif ( $start && $start eq 'Add an item type' ){
     my $itemtypes = Koha::ItemTypes->search();
     warn $itemtypes;
     $template->param(
             itemtypes => $itemtypes,
    );

#Check if the $step variable equals 1 i.e. the user has clicked to create a library in the create library screen 1 
}elsif ( $step && $step == 1 ) {

    my $createlibrary = $query->param('createlibrary'); #Store the inputted library branch code and name in $createlibrary
    $template->param('createlibrary'=>$createlibrary); # Hand the library values back to the template in the createlibrary variable

    #store inputted parameters in variables
    my $branchcode       = $input->param('branchcode');
    my $categorycode     = $input->param('categorycode');
    my $op               = $input->param('op') || 'list';
    my @messages;
    my $library;

    #Take the text 'branchname' and store it in the @fields array
    my @fields = qw(
        branchname
    ); 

    $branchcode =~ s|\s||g; # Use a regular expression to check the value of the inputted branchcode 

    #Create a new library object and store the branchcode and @fields array values in this new library object
    my $library = Koha::Library->new(
        {   branchcode => $branchcode, 
            ( map { $_ => scalar $input->param($_) || undef } @fields )
        }
    );

#Create Patron category
    eval { $library->store; }; #Use the eval{} function to store the library object

    #If there are values in the $@ then push the values type => 'alert', code => 'error_on_insert' into the @messages array el    se push the values type => 'message', code => 'success_on_insert' to that array
    if ($@) {
        push @messages, { type => 'alert', code => 'error_on_insert' };
    } else {
        push @messages, { type => 'message', code => 'success_on_insert' };
    }

#Check if the $step vairable equals 2 i.e. the user has clicked to create a patron category in the create patron category screen 1
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

#Create item type
}elsif ( $step && $step == 4){
    my $input = new CGI;
    my $itemtype_code = $input->param('itemtype');
    my $op = $input->param('op') // 'list';
    my @messages;

    my( $template, $borrowernumber, $cookie) = get_template_and_user(
            {   template_name   => "/onboarding/onboardingstep4.tt",
                query           => $input,
                type            => "intranet",
                authnotrequired => 0,
                flagsrequired   => { parameters => 'parameters_remaining_permissions'},
                debug           => 1,
            }
    );

    if($op eq 'add_form'){
        my $itemtype = Koha::ItemTypes->find($itemtype_code);
        template->param(itemtype=>$itemtype,);
    }elsif($op eq 'add_validate'){
        my $itemtype = Koha::ItemTypes->find($itemtype_code);
        my $description = $input->param('description');

        #store the input from the form - only 2 fields 
        my $itemtype= Koha::ItemType->new(
            { itemtype    => $itemtype_code,
              description => $description,
            }
        );
        eval{ $itemtype->store; };
        #Error messages
        if($@){
            push @messages, {type=> 'error', code => 'error_on_insert'};
        }else{
            push @messages, {type=> 'message', code => 'success_on_insert'};
        }
    }

}elsif ( $step && $step == 5){
    #Fetching all the existing categories to display in a drop down box
    my $categories;
    $categories= Koha::Patron::Categories->search();
    $template->param(
        categories => $categories,
    );

    my $itemtypes;
    $itemtypes= Koha::ItemTypes->search();
    $template->param(
        itemtypes => $itemtypes,
    );

    my $input = CGI->new;
    my($template, $loggedinuser, $cookie)  =get_template_and_user({
            template_name => "/onboarding/onboardingstep5.tt",
            query => $input,
            type => "intranet",
            authnotrequired=>0,
            flagsrequired=> {parameters => 'manage_circ_rules'},
            debug =>1,
    });
    
    my $type = $input->param('type');
    my $branch = $input->param('branch');
    
    
    
    if($op eq 'add_form'){



    }
    elsif($op eq 'add_validate'){
        my $bor = $input->param('categorycode');
        my $itemtype = $input->param('itemtype');
        my $maxissueqty = $input->param('maxissueqty');
        my $issuelength = $input->param('issuelength');
        #$issuelength = $issuelength eq q{} ? undef : $issuelength;
        my $lengthunit = $input->param('lengthunit');
        my $renewalsallowed = $input->param('renewalsallowed');
        my $renewalperiod = $input->param('renewalperiod');
        my $onshelfholds = $input->param('onshelfholds');
   
    }
    



}




output_html_with_http_headers $input, $cookie, $template->output;

