# --
# Copyright (C) 2001-2017 OTRS AG, http://otrs.com/
# --
# This software comes with ABSOLUTELY NO WARRANTY. For details, see
# the enclosed file COPYING for license information (AGPL). If you
# did not receive this file, see http://www.gnu.org/licenses/agpl.txt.
# --

use strict;
use warnings;
use utf8;

use vars (qw($Self));

# Get selenium object.
my $Selenium = $Kernel::OM->Get('Kernel::System::UnitTest::Selenium');

$Selenium->RunTest(
    sub {

        # Get helper object.
        my $Helper = $Kernel::OM->Get('Kernel::System::UnitTest::Helper');

        # Do not check RichText and hide Fred.
        for my $SySConfig (qw(Frontend::RichText Fred::Active)) {
            $Helper->ConfigSettingChange(
                Valid => 1,
                Key   => $SySConfig,
                Value => 0
            );
        }

        # Enable FormDrafts in AgentTicketActionCommon screens.
        for my $SySConfig (qw(Outbound Inbound)) {
            $Helper->ConfigSettingChange(
                Valid => 1,
                Key   => "Ticket::Frontend::AgentTicketPhone${SySConfig}###FormDraft",
                Value => 1
            );
        }

        # Get ticket object.
        my $TicketObject = $Kernel::OM->Get('Kernel::System::Ticket');

        # Create test ticket.
        my $TicketID = $TicketObject->TicketCreate(
            Title        => 'Selenium Test Ticket',
            Queue        => 'Raw',
            Lock         => 'unlock',
            Priority     => '3 normal',
            State        => 'new',
            CustomerID   => 'SeleniumCustomer',
            CustomerUser => 'SeleniumCustomer@localhost.com',
            OwnerID      => 1,
            UserID       => 1,
        );
        $Self->True(
            $TicketID,
            "Ticket ID $TicketID is created",
        );

        # Get RandomID.
        my $RandomID = $Helper->GetRandomID();

        # Create test user and login.
        my $TestUserLogin = $Helper->TestUserCreate(
            Groups => [ 'admin', 'users' ],
        ) || die "Did not get test user";

        $Selenium->Login(
            Type     => 'Agent',
            User     => $TestUserLogin,
            Password => $TestUserLogin,
        );

        # Get script alias.
        my $ScriptAlias = $Kernel::OM->Get('Kernel::Config')->Get('ScriptAlias');

        # Navigate to zoom view of created test ticket.
        $Selenium->VerifiedGet("${ScriptAlias}index.pl?Action=AgentTicketZoom;TicketID=$TicketID");

        # Create test case matrix.
        my @Tests = (
            {
                Module => 'Outbound',
                Fields => {
                    State => {
                        ID     => 'NextStateID',
                        Type   => 'DropDown',
                        Value  => 3,
                        Update => 7,
                    },
                    Subject => {
                        ID     => 'Subject',
                        Type   => 'Input',
                        Value  => 'Selenium Outbound Subject',
                        Update => 'Selenium OutBound Subject - Update'
                    },
                    Body => {
                        ID     => 'RichText',
                        Type   => 'Input',
                        Value  => 'Selenium Outbound Body',
                        Update => 'Selenium Outbound Body - Update',
                    },
                },
            },
            {
                Module => 'Inbound',
                Fields => {
                    State => {
                        ID     => 'NextStateID',
                        Type   => 'DropDown',
                        Value  => 3,
                        Update => 7,
                    },
                    Subject => {
                        ID     => 'Subject',
                        Type   => 'Input',
                        Value  => 'Selenium Inbound Subject',
                        Update => 'Selenium Inbound Subject - Update'
                    },
                    Body => {
                        ID     => 'RichText',
                        Type   => 'Input',
                        Value  => 'Selenium Inbound Body',
                        Update => 'Selenium Inbound Body - Update',
                    },
                },
            },
        );

        # Execute test scenarios.
        for my $Test (@Tests) {

            # Create FormDraft name.
            my $Title = $Test->{Module} . 'FormDraft' . $RandomID;

            # Force sub menus to be visible in order to be able to click one of the links.
            $Selenium->WaitFor(
                JavaScript =>
                    'return typeof($) === "function" && $("#nav-Communication ul").css({ "height": "auto", "opacity": "100" });'
            );

            # Click on module and switch window.
            $Selenium->find_element(
                "//a[contains(\@href, \'Action=AgentTicketPhone$Test->{Module};TicketID=$TicketID' )]"
            )->VerifiedClick();

            $Selenium->WaitFor( WindowCount => 2 );
            my $Handles = $Selenium->get_window_handles();
            $Selenium->switch_to_window( $Handles->[1] );

            # Wait until page has loaded, if necessary.
            $Selenium->WaitFor(
                JavaScript =>
                    'return typeof($) === "function" && $("#submitRichText").length;'
            );

            # Input fields.
            for my $Field ( sort keys %{ $Test->{Fields} } ) {

                if ( $Test->{Fields}->{$Field}->{Type} eq 'DropDown' ) {
                    $Selenium->execute_script(
                        "\$('#$Test->{Fields}->{$Field}->{ID}').val('$Test->{Fields}->{$Field}->{Value}').trigger('redraw.InputField').trigger('change');"
                    );
                }
                else {
                    $Selenium->find_element( "#$Test->{Fields}->{$Field}->{ID}", 'css' )->clear();
                    $Selenium->find_element( "#$Test->{Fields}->{$Field}->{ID}", 'css' )
                        ->send_keys( $Test->{Fields}->{$Field}->{Value} );
                }
            }

            # Create FormDraft and submit.
            $Selenium->find_element( "#FormDraftSave", 'css' )->VerifiedClick();
            $Selenium->WaitFor(
                JavaScript =>
                    'return typeof($) === "function" && $("#FormDraftTitle").length;'
            );
            $Selenium->find_element( "#FormDraftTitle", 'css' )->send_keys($Title);
            $Selenium->find_element( "#SaveFormDraft",  'css' )->click();

            # Switch back window.
            $Selenium->WaitFor( WindowCount => 1 );
            $Selenium->switch_to_window( $Handles->[0] );

            # Refresh screen.
            $Selenium->VerifiedRefresh();

            # Verify FormDraft is created in zoom screen.
            $Self->True(
                index( $Selenium->get_page_source(), $Title ) > -1,
                "FormDraft for $Test->{Module} $Title is found",
            );

            # Get article object.
            my $ArticleObject = $Kernel::OM->Get('Kernel::System::Ticket::Article');
            my $ArticleBackendObject = $ArticleObject->BackendForChannel( ChannelName => 'Phone' );

            # Create test Article to trigger that draft is outdated.
            my $ArticleID = $ArticleBackendObject->ArticleCreate(
                TicketID             => $TicketID,
                SenderType           => 'customer',
                Subject              => "Article $Test->{Module} OutDate FormDraft trigger",
                Body                 => 'Selenium body article',
                Charset              => 'ISO-8859-15',
                MimeType             => 'text/plain',
                HistoryType          => 'AddNote',
                HistoryComment       => 'Some free text!',
                UserID               => 1,
                IsVisibleForCustomer => 1,
            );
            $Self->True(
                $ArticleID,
                "Article ID $ArticleID is created",
            );

            # Refresh screen.
            $Selenium->VerifiedRefresh();

            # Click on test created FormDraft and switch window.
            $Selenium->find_element(
                "//a[contains(\@href, \'Action=AgentTicketPhone$Test->{Module};TicketID=$TicketID;LoadFormDraft=1' )]"
            )->VerifiedClick();

            $Selenium->WaitFor( WindowCount => 2 );
            $Handles = $Selenium->get_window_handles();
            $Selenium->switch_to_window( $Handles->[1] );

            # Wait until page has loaded, if necessary.
            $Selenium->WaitFor(
                JavaScript =>
                    'return typeof($) === "function" && $("#submitRichText").length;'
            );

            # Make sure that outdated notification is present.
            $Self->True(
                index( $Selenium->get_page_source(), "You have loaded the draft \"$Title\"" ) > 0,
                'Draft loaded notification is present',
            );

            # Make sure that outdated notification is present.
            $Self->True(
                index(
                    $Selenium->get_page_source(),
                    "Please note that this draft is outdated because the ticket was modified since this draft was created."
                    )
                    > 0,
                'Outdated notification is present',
            );

            # Verify initial FormDraft values and update them.
            for my $FieldValue ( sort keys %{ $Test->{Fields} } ) {

                if ( $Test->{Fields}->{$FieldValue}->{Type} eq 'DropDown' ) {
                    $Self->Is(
                        $Selenium->execute_script("return \$('#$Test->{Fields}->{$FieldValue}->{ID}').val()"),
                        $Test->{Fields}->{$FieldValue}->{Value},
                        "Initial FormDraft value for $Test->{Module} field $FieldValue is correct"
                    );

                    $Selenium->execute_script(
                        "\$('#$Test->{Fields}->{$FieldValue}->{ID}').val('$Test->{Fields}->{$FieldValue}->{Update}').trigger('redraw.InputField').trigger('change');"
                    );
                }
                else {
                    $Self->Is(
                        $Selenium->find_element( "#$Test->{Fields}->{$FieldValue}->{ID}", 'css' )->get_value(),
                        $Test->{Fields}->{$FieldValue}->{Value},
                        "Initial FormDraft value for $Test->{Module} field $FieldValue is correct"
                    );

                    $Selenium->find_element( "#$Test->{Fields}->{$FieldValue}->{ID}", 'css' )->clear();
                    $Selenium->find_element( "#$Test->{Fields}->{$FieldValue}->{ID}", 'css' )
                        ->send_keys( $Test->{Fields}->{$FieldValue}->{Update} );
                }
            }

            $Selenium->find_element( "#FormDraftUpdate", 'css' )->click();

            # Switch back window.
            $Selenium->WaitFor( WindowCount => 1 );
            $Selenium->switch_to_window( $Handles->[0] );

            # Refresh screen.
            $Selenium->VerifiedRefresh();

            # Click on test created FormDraft and switch window.
            $Selenium->find_element(
                "//a[contains(\@href, \'Action=AgentTicketPhone$Test->{Module};TicketID=$TicketID;LoadFormDraft=1' )]"
            )->VerifiedClick();

            $Selenium->WaitFor( WindowCount => 2 );
            $Handles = $Selenium->get_window_handles();
            $Selenium->switch_to_window( $Handles->[1] );

            # Wait until page has loaded, if necessary.
            $Selenium->WaitFor(
                JavaScript =>
                    'return typeof($) === "function" && $("#submitRichText").length;'
            );

            # Verify updated FormDraft values.
            for my $FieldValue ( sort keys %{ $Test->{Fields} } ) {

                if ( $Test->{Fields}->{$FieldValue}->{Type} eq 'DropDown' ) {
                    $Self->Is(
                        $Selenium->execute_script("return \$('#$Test->{Fields}->{$FieldValue}->{ID}').val()"),
                        $Test->{Fields}->{$FieldValue}->{Update},
                        "Updated FormDraft value for $Test->{Module} field $FieldValue is correct"
                    );
                }
                else {
                    $Self->Is(
                        $Selenium->find_element( "#$Test->{Fields}->{$FieldValue}->{ID}", 'css' )->get_value(),
                        $Test->{Fields}->{$FieldValue}->{Update},
                        "Updated FormDraft value for $Test->{Module} field $FieldValue is correct"
                    );
                }
            }

            $Selenium->close();

            # Switch back window.
            $Selenium->WaitFor( WindowCount => 1 );
            $Selenium->switch_to_window( $Handles->[0] );

            # Refresh screen.
            $Selenium->VerifiedRefresh();

            # Delete draft
            $Selenium->find_element( ".FormDraftDelete", 'css' )->VerifiedClick();
            $Selenium->WaitFor(
                JavaScript =>
                    'return typeof($) === "function" && $("#DeleteConfirm").length;'
            );
            $Selenium->find_element( "#DeleteConfirm", 'css' )->VerifiedClick();

            $Selenium->WaitFor(
                JavaScript =>
                    'return typeof($) === "function" && $(".FormDraftDelete").length==0;'
            ) || die 'FormDraft was not deleted!';
        }

        # Delete created test ticket.
        my $Success = $TicketObject->TicketDelete(
            TicketID => $TicketID,
            UserID   => 1,
        );
        $Self->True(
            $Success,
            "Ticket ID $TicketID is deleted"
        );
    }

);

1;