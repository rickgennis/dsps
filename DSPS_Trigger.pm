package DSPS_Trigger;

use DSPS_String;
use DSPS_Util;
use DSPS_Debug;
use DSPS_User;
use DSPS_Room;
use strict;
use warnings;

use base 'Exporter';
our @EXPORT = ('%g_hTriggers', 'createOrReplaceTrigger', 'checkAllTriggers', 'triggerStatus');

our %g_hTriggers;



sub createOrReplaceTrigger {
    my $rhTrig = {
        name               => $_[0],
        message_to_users   => $_[1],
        event_match_string => $_[2],
        required_user      => $_[3],
        command            => $_[4],
        locked             => 0,
        last_tripped       => 0,
    };

    $g_hTriggers{ $_[0] } = $rhTrig;
}



sub listTriggers() {
    my $sResult = '';

    foreach my $sTrig (sort keys %g_hTriggers) {
        $sResult .=
            ($sResult                       ? "\n" : '')
          . ($g_hTriggers{$sTrig}->{locked} ? '-'  : '+')
          . "$sTrig"
          . ($g_hTriggers{$sTrig}->{last_tripped} ? (' (' . prettyDateTime($g_hTriggers{$sTrig}->{last_tripped}) . ')') : '');
    }

    return ("Triggers:\n" . ($sResult ? $sResult : '  None.'));
}



sub armTriggers($) {
    my $sRegex  = shift;
    my $sResult = '';

    foreach my $sTrig (sort keys %g_hTriggers) {
        if ($sTrig =~ /$sRegex/i) {
            if ($g_hTriggers{$sTrig}->{locked}) {
                $g_hTriggers{$sTrig}->{locked} = 0;
                $sResult .= ($sResult ? "\n" : '') . "Trigger '$sTrig' is now armed.";
            }
            else {
                $sResult .= ($sResult ? "\n" : '') . "Trigger '$sTrig' was already armed.";
            }
        }
    }

    return $sResult;
}



sub disarmTriggers($) {
    my $sRegex  = shift;
    my $sResult = '';

    foreach my $sTrig (sort keys %g_hTriggers) {
        if ($sTrig =~ /$sRegex/i) {
            if ($g_hTriggers{$sTrig}->{locked}) {
                $sResult .= ($sResult ? "\n" : '') . "Trigger '$sTrig' is not currently armed.";
            }
            else {
                $g_hTriggers{$sTrig}->{locked} = 1;
                $sResult .= ($sResult ? "\n" : '') . "Trigger '$sTrig' is now temporarily disarmed.";
            }
        }
    }

    return $sResult;
}



sub checkAllTriggers($$) {
    my $iUser    = shift;
    my $sMessage = shift;

    foreach my $sTrig (keys %g_hTriggers) {

        # does the user match
        if ($g_hUsers{$iUser}->{name} eq $g_hTriggers{$sTrig}->{required_user}) {

            # does the message match
            my $sRegex = $g_hTriggers{$sTrig}->{event_match_string};
            if (my @aBackRefs = ($sMessage =~ /$sRegex/is)) {

                # setup trigger variables and interpolate regexes from the message
                my $sName           = $g_hTriggers{$sTrig}->{name};
                my $sMessageToUsers = $g_hTriggers{$sTrig}->{message_to_users};
                my $sCommand        = $g_hTriggers{$sTrig}->{command};
                $sMessageToUsers =~ s/(?<!\\)\$(\d+)/$aBackRefs[$1 - 1]/g;
                $sCommand =~ s/(?<!\\)\$(\d+)/$aBackRefs[$1 - 1]/g;

                # PROBLEM
                if ($sMessage =~ main::getProblemRegex()) {

                    # if not already locked then we have an armed trigger successfully triggered
                    if (!$g_hTriggers{$sTrig}->{locked}) {
                        $g_hTriggers{$sTrig}->{locked}       = 1;
                        $g_hTriggers{$sTrig}->{last_tripped} = time();

                        debugLog(D_trigger, "matched $sName; $sMessageToUsers");
                        main::sendCustomSystemMessageToRoom($iUser, "DSPS Trigger $sName: $sMessageToUsers", 1);
                        main::forkExecCommand($sCommand);
                    }
                    else {
                        debugLog(D_trigger, "matched $sName but trigger still locked from previous run");
                        main::sendCustomSystemMessageToRoom($iUser, "DSPS Trigger $sName: didn't rearm from previous run (i.e. no recovery) - NOT firing.", 1);
                    }
                }

                # RECOVERY
                elsif ($sMessage =~ main::getRecoveryRegex()) {
                    debugLog(D_trigger, "matched $sName; recovery");

                    $g_hTriggers{$sTrig}->{locked} = 0;
                    main::sendCustomSystemMessageToRoom($iUser, "DSPS Trigger $sName: rearmed.", 1);

                    # NOTE: Don't change the syntax of the above string without making the same update
                    # to the regex in DSPS_User::blockedByFilter().
                }
            }

        }
    }
}



sub triggerStatus() {
    my $sResult = '';

    foreach my $sTrig (sort keys %g_hTriggers) {
        my $sLast = $g_hTriggers{$sTrig}->{last_tripped};
        $sResult .= "Trigger '$sTrig' is " . ($g_hTriggers{$sTrig}->{locked} ? 'locked' : 'armed') . ($sLast ? " [" . prettyDateTime($sLast) . "]" : '') . ".\n";
    }

    return $sResult;
}

1;
