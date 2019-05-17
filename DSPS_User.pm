package DSPS_User;

use FreezeThaw qw(freeze thaw);
use DSPS_Debug;
use DSPS_Util;
use DSPS_String;
use strict;
use warnings;

use base 'Exporter';
our @EXPORT = ('%g_hUsers', '%g_hAmbigNames', 'UID');

our %g_hUsers;
our %g_hAmbigNames;
my %hDedupeByMessage;
my $iLastDedupeMaintTime = 0;



sub createUser {
    my $rhUser = {
        name              => $_[0],
        regex             => $_[1],
        phone             => $_[2],
        group             => $_[3],
        access_level      => $_[4] || 0,
        auto_include      => '',
        via               => '',
        macros            => {},
        filter_recoveries => 0,
        vacation_end      => 0,
        staycation_end    => 0,
        auto_reply_text   => '',
        auto_reply_expire => 0,
        throttle          => 0,
        valid_end         => 0,
    };

    $g_hUsers{ $_[2] } = $rhUser;
    debugLog(D_users, "created $_[0] ($_[2]) of $_[3]");

    return $rhUser;
}



sub previouslySentTo($$) {
    my $iSender  = shift;
    my $sMessage = shift;

    if (defined $hDedupeByMessage{$sMessage}) {
        if ($hDedupeByMessage{$sMessage} =~ /\b$iSender:(\d+)\b/) {
            my $iTime = $1;
            return 1 if ($iTime > $main::g_iLastWakeTime - 172800);

            $hDedupeByMessage{$sMessage} =~ s/$iSender:$iTime/$iSender:$main::g_iLastWakeTime/;
            return 0;
        }
    }

    $hDedupeByMessage{$sMessage} = ($hDedupeByMessage{$sMessage} ? $hDedupeByMessage{$sMessage} : '') . " $iSender:" . $main::g_iLastWakeTime;
    return 0;
}



sub getAutoReply($) {
    my $iUser = shift;

    if ($g_hUsers{$iUser}->{auto_reply_text} && $g_hUsers{$iUser}->{auto_reply_expire}) {
        if ($g_hUsers{$iUser}->{auto_reply_expire} > $main::g_iLastWakeTime) {
            return $g_hUsers{$iUser}->{auto_reply_text};
        }
        else {
            debugLog(D_users, "auto reply for user " . $g_hUsers{$iUser}->{name} . " has expired; deleting.");
            $g_hUsers{$iUser}->{auto_reply_expire} = 0;
            $g_hUsers{$iUser}->{auto_reply_text}   = '';
        }
    }

    return '';
}



sub freezeState() {
    my %hUserState;

    # create a hash of the user configurable settings
    foreach my $iUser (keys %g_hUsers) {
        $hUserState{$iUser}->{filter_recoveries} = $g_hUsers{$iUser}->{filter_recoveries};
        $hUserState{$iUser}->{vacation_end}      = $g_hUsers{$iUser}->{vacation_end};
        $hUserState{$iUser}->{staycation_end}    = $g_hUsers{$iUser}->{staycation_end};
        $hUserState{$iUser}->{auto_reply_text}   = $g_hUsers{$iUser}->{auto_reply_text};
        $hUserState{$iUser}->{auto_reply_expire} = $g_hUsers{$iUser}->{auto_reply_expire};
        $hUserState{$iUser}->{macros}            = $g_hUsers{$iUser}->{macros};
    }

    return freeze(%hUserState);
}



sub freezeMessageState() {
    return freeze(%hDedupeByMessage);
}



sub thawMessageState($) {
    eval {%hDedupeByMessage = thaw(shift);};
    return infoLog("Unable to parse user message state data - ignoring") if ($@);
}



sub thawState($) {
    my %hUserState;

    eval {%hUserState = thaw(shift);};
    return infoLog("Unable to parse user state data - ignoring") if ($@);

    foreach my $iUser (keys %hUserState) {

        # we only want to update information for users that already exist.  users will already
        # exist after a restart because they're created by readConfig().  by only restoring
        # attributes of existing users that allows users the admin has deleted from the config
        # file to fall out of the state data too.
        if (defined $g_hUsers{$iUser}) {
            $g_hUsers{$iUser}->{filter_recoveries} = $hUserState{$iUser}->{filter_recoveries};
            $g_hUsers{$iUser}->{vacation_end}      = $hUserState{$iUser}->{vacation_end};
            $g_hUsers{$iUser}->{staycation_end}    = $hUserState{$iUser}->{staycation_end};
            $g_hUsers{$iUser}->{auto_reply_text}   = $hUserState{$iUser}->{auto_reply_text};
            $g_hUsers{$iUser}->{auto_reply_expire} = $hUserState{$iUser}->{auto_reply_expire};
            $g_hUsers{$iUser}->{macros}            = $hUserState{$iUser}->{macros};
            debugLog(D_state, "restored state data for user " . $g_hUsers{$iUser}->{name});
        }
    }
}



sub matchUserByName($) {
    my $sName = shift;

    foreach my $sPhone (keys %g_hUsers) {
        debugLog(D_users, "checking $sName against " . $g_hUsers{$sPhone}->{name});
        if (lc($sName) eq lc($g_hUsers{$sPhone}->{name})) {
            return $sPhone;
        }
    }

    return '';
}



sub matchUserByRegex($) {
    my $sName = shift;

    foreach my $sPhone (keys %g_hUsers) {
        if ($sName =~ /\b($g_hUsers{$sPhone}->{regex})\b/i) {
            return $sPhone;
        }
    }

    return '';
}



sub usersInGroup($) {
    my $sTargetGroup = shift;
    my @aUsers;

    foreach my $iUser (keys %g_hUsers) {
        push(@aUsers, $iUser) if ($g_hUsers{$iUser}->{group} eq $sTargetGroup);
    }

    return @aUsers;
}



sub allGroups() {
    my %hGroups;

    foreach my $iUser (keys %g_hUsers) {
        $hGroups{ $g_hUsers{$iUser}->{group} } = 1 if $g_hUsers{$iUser}->{group};
    }

    return keys(%hGroups);
}



sub humanTest($) {
    my $sName = shift;

    return ($sName !~ /^\!/);
}



sub humanUsersPhone($) {
    my $iUser = shift;

    # default to true if the user isn't defined -- for opt-in subscriptions we need
    # to assume anyone not defined in dsps.conf is actually human (mostly)
    return (defined $g_hUsers{$iUser} ? humanTest($g_hUsers{$iUser}->{name}) : 1);
}


sub UID($) {
    my $iUser = shift;
    
    return (defined $g_hUsers{$iUser} ? $g_hUsers{$iUser}->{name} : $iUser);
}


sub usersHealthCheck() {
    # check for expired vacation time
    # check for expired staycation time
    # check for expired users
    foreach my $iUser (keys %g_hUsers) {
        if ($g_hUsers{$iUser}->{vacation_end} && ($g_hUsers{$iUser}->{vacation_end} <= $main::g_iLastWakeTime)) {
            $g_hUsers{$iUser}->{vacation_end} = 0;
            debugLog(D_users, $g_hUsers{$iUser}->{name} . "'s vacation time has expired");
            main::sendEmail(main::getUsersEscalationsEmails($iUser), main::getAdminEmail(), sv(E_VacationElapsed1, $g_hUsers{$iUser}->{name}));
        }

        if ($g_hUsers{$iUser}->{staycation_end} && ($g_hUsers{$iUser}->{staycation_end} <= $main::g_iLastWakeTime)) {
            $g_hUsers{$iUser}->{staycation_end} = 0;
            debugLog(D_users, $g_hUsers{$iUser}->{name} . "'s staycation time has expired");
            main::sendEmail(main::getUsersEscalationsEmails($iUser), main::getAdminEmail(), sv(E_StaycationElapsed1, $g_hUsers{$iUser}->{name}));
        }

        if ($g_hUsers{$iUser}->{valid_end} && ($g_hUsers{$iUser}->{valid_end} <= $main::g_iLastWakeTime)) {
            debugLog(D_users, $g_hUsers{$iUser}->{name} . " is no longer valid; dropping from running config");
            debugLog(D_pageEngine, "emailing about no-longer-valid user " . $g_hUsers{$iUser}->{name});
            main::sendEmail(main::getAdminEmail(), '', sv(E_UserInvalidated1, $g_hUsers{$iUser}->{name}));

	    # the below 3 calls (dropUserFromAllEscalations, delete and writeConfig) have to happen in this order - internal assumptions require it
	    main::dropUserFromAllEscalations($iUser);
            delete($g_hUsers{$iUser});

	    if (my $sError = main::writeConfig()) {
		main::sendEmail(main::getAdminEmail(), '',
		"Subject: DSPS Error in DSPS_Config::writeConfig()\n\n"
		. "After auto dropping a user, DSPS was unable to write the new config file to disk:\n$sError");
	    }
        }
    }

    # check for expired message cache entries every 6 hours
    # structure of this cache is a hash keyed on message content with
    # each hash entry being a string of CELLNUMBER:LAST_SEND_TIME
    # that way it's fast to find a given message and update who it went to.
    # we use this to determine if that exact message has gone to a specific
    # phone before.  if so (and it's been within the last 2 days) we can add
    # a random char to the end of the message to make it unique (done in
    # previouslySentTo().  otherwise the text gateway company drops what it
    # thinks is a dupe message to the phone.
    if ($iLastDedupeMaintTime < $main::g_iLastWakeTime - 21600) {
        $iLastDedupeMaintTime = $main::g_iLastWakeTime;

        my $iBeforeCount = keys %hDedupeByMessage;
        foreach my $sMessage (keys %hDedupeByMessage) {
            my $sData = $hDedupeByMessage{$sMessage};

            foreach my $sDataPair (split(/\s+/, $sData)) {
                next unless $sDataPair;

                if ($sDataPair =~ /\b(\d+):(\d+)\b/) {
                    my $iPhone = $1;
                    my $iTime  = $2;
                    $sData =~ s/$iPhone:$iTime// if ($iTime < $main::g_iLastWakeTime - 172800);
                }
                else {
                    $sData =~ s/$sDataPair//;
                }
            }

            if ($sData =~ /^\s*$/) {
                delete $hDedupeByMessage{$sMessage};
            }
            else {
                $hDedupeByMessage{$sMessage} = $sData;
            }
        }

        my $iAfterCount = keys %hDedupeByMessage;
        my $iDiff = $iBeforeCount - $iAfterCount;
        debugLog(D_users | D_pageEngine, "cleaned up deduping hash ($iDiff entr" . ($iDiff == 1 ? 'y' : 'ies') . " removed, $iAfterCount remaining)") if ($iDiff || $iAfterCount);
        main::saveState();
    }
}



sub blockedByFilter($$$) {
    my $iPhone           = shift;
    my $rMessage         = shift;
    my $iLastProblemTime = shift;
    my $sMessage         = ${$rMessage};
    my $sRecoveryRegex   = main::getRecoveryRegex();
    my $sProblemRegex    = main::getProblemRegex();
    my $sRearmedRegex    = 'DSPS Trigger.*rearmed';
    use constant THROTTLE_PAGES => 5;

    # FITLER:  Recoveries per user
    if ($sRecoveryRegex && ($g_hUsers{$iPhone}->{filter_recoveries} == 1) && (($sMessage =~ /$sRecoveryRegex/) || ($sMessage =~ /$sRearmedRegex/))) {
        debugLog(D_users, "blocked for " . $g_hUsers{$iPhone}->{name} . " ($iPhone) [NoRecovery]: $sMessage");
        return 'noRecovery';
    }

    # FILTER:  Smart recoveries per user
    # Smart recoveries means to let the recovery through if it during the day or [when night] if it's within 5 minutes
    # of the last problem page
    if (   $sRecoveryRegex
        && ($g_hUsers{$iPhone}->{filter_recoveries} == 2)
        && (($sMessage =~ /$sRecoveryRegex/) || ($sMessage =~ /$sRearmedRegex/))
        && !isDuringWakingHours()
        && ($main::g_iLastWakeTime - $iLastProblemTime > 300))
    {
        debugLog(D_users, "blocked for " . $g_hUsers{$iPhone}->{name} . " ($iPhone) [SmartRecovery]: $sMessage");
        return 'smartRecovery';
    }

    # FILTER:  Rate Throttling
    if (($g_hUsers{$iPhone}->{throttle}) && ($g_hUsers{$iPhone}->{throttle} =~ /(\d+)\/(\d+)/)) {
        my $iCount    = $1;
        my $iLastTime = $2;

        if ($main::g_iLastWakeTime - $iLastTime > 60) {
            $g_hUsers{$iPhone}->{throttle} = '1/' . $main::g_iLastWakeTime;
        }
        else {
            $g_hUsers{$iPhone}->{throttle} = $iCount + 1 . '/' . $iLastTime;

            if (($sMessage =~ /$sProblemRegex/) && ($iCount > (2 * THROTTLE_PAGES + 1))) {
                if (main::getAllNagiosFilterTillGlobal() < $main::g_iLastWakeTime) {
                    main::setAllNagiosFilterTillGlobal($main::g_iLastWakeTime + 60 * 30);    # half hour
                    $g_hUsers{$iPhone}->{throttle} = '';
                    main::sendCustomSystemMessageToRoom($iPhone, S_AutoNagiosMute, 2);
                    return 1;
                }
            }

            if ($iCount > THROTTLE_PAGES - 1) {
                debugLog(D_users, "PAGE THROTTLED ($iPhone): $sMessage");
                return 'throttled';
            }
            elsif (($iCount == THROTTLE_PAGES - 1) && ($sMessage !~ /^Throttled::/)) {
                $$rMessage = 'Throttled::' . $sMessage;
            }
        }
    }
    else {
        $g_hUsers{$iPhone}->{throttle} = '1/' . $main::g_iLastWakeTime;
    }

    return 0;
}

1;

