package DSPS_SystemFilter;

use FreezeThaw qw(freeze thaw);
use Time::Local;
use DSPS_User;
use DSPS_Room;
use DSPS_Config;
use DSPS_String;
use DSPS_Debug;
use strict;
use warnings;

use base 'Exporter';
our @EXPORT = ('getAllNagiosFilterTill', 'setAllNagiosFilterTill');

our $iFilterRecoveryLoadTill = 0;
our $iFilterAllNagiosTill    = 0;
our %rFilterRegex;
our %rFilterRegexProfile;



sub freezeState() {
    my %hFilterState;

    $hFilterState{recovery} = $iFilterRecoveryLoadTill;
    $hFilterState{all}      = $iFilterAllNagiosTill;
    $hFilterState{regex}    = \%rFilterRegex;

    return freeze(%hFilterState);
}



sub thawState($) {
    my %hFilterState;

    eval {%hFilterState = thaw(shift);};
    return infoLog("Unable to parse filter state data - ignoring") if ($@);

    $iFilterRecoveryLoadTill = $hFilterState{recovery};
    $iFilterAllNagiosTill    = $hFilterState{all};
    %rFilterRegex            = %{ $hFilterState{regex} };
    debugLog(D_state, "restored filter state data (regexes: " . keys(%rFilterRegex) . ")");
}



sub blockedByFilter($$) {
    my $sMessage = shift;
    my $iRoom    = shift;

    # check the recovery or system load filter
    if (($iFilterRecoveryLoadTill > $main::g_iLastWakeTime) && ($sMessage =~ /(^[-+!]{0,1}RECOVERY)|(System Load)/s)) {
        debugLog(D_filters, "message matched Recovery or Load filter");
        return "recovery/load";
    }

    # check the all nagios filter
    if (($iFilterAllNagiosTill > $main::g_iLastWakeTime) && (($sMessage =~ /$g_hConfigOptions{nagios_problem_regex}/s) || ($sMessage =~ /$g_hConfigOptions{nagios_recovery_regex}/s))) {
        debugLog(D_filters, "message matched All Nagios filter");
        return "allNagios";
    }

    # check all regex filters
    foreach my $iRegexFilterID (keys %rFilterRegex) {
        my $sThisRegex = $rFilterRegex{$iRegexFilterID}->{regex};
        $sThisRegex =~ s/(\\s| )/(\\s|)/g;  # to match randomly inserted newlines by the gateway provider
	debugLog(D_filters, "considering regex filter /$sThisRegex/");

        if (($rFilterRegex{$iRegexFilterID}->{till} >= $main::g_iLastWakeTime) && ($sMessage =~ /$sThisRegex/is)) {
            debugLog(D_filters, "message matched Regex filter (" . $rFilterRegex{$iRegexFilterID}->{regex} . ")");
            return "regex";
        }

        rmRegexFilter($rFilterRegex{$iRegexFilterID}->{regex}) if ($rFilterRegex{$iRegexFilterID}->{till} < $main::g_iLastWakeTime);
    }

    # check all regex profiles
    unless ($iRoom && $g_hRooms{$iRoom}->{maintenance}) {
        foreach my $iRegexFilterID (keys %rFilterRegexProfile) {
            my $sThisRegex = $rFilterRegexProfile{$iRegexFilterID}->{regex};
            $sThisRegex =~ s/(\\s| )/(\\s|)/g;  # to match randomly inserted newlines by the gateway provider
            if ($sMessage =~ /$sThisRegex/is) {
                my ($iFromHour, $iFromMin) = ($rFilterRegexProfile{$iRegexFilterID}->{from} =~ /(\d+):(\d+)/);
                my ($iTillHour, $iTillMin) = ($rFilterRegexProfile{$iRegexFilterID}->{till} =~ /(\d+):(\d+)/);
                my $iFrom = $iFromHour * 3600 + $iFromMin * 60;
                my $iTill = $iTillHour * 3600 + $iTillMin * 60;
                my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime($main::g_iLastWakeTime);
                my $iMidnight = timelocal(0, 0, 0, $mday, $mon, $year);
                my $iNowToday = $main::g_iLastWakeTime - $iMidnight;

                # debugLog(D_filters, "checking regex profile (/$sThisRegex/); now=$iNowToday, window=$iFrom-$iTill");
                if (($iFrom < $iTill && $iNowToday >= $iFrom && $iNowToday <= $iTill) ||
                    ($iFrom > $iTill && ($iNowToday >= $iFrom || $iNowToday <= $iTill))) {
                    debugLog(D_filters, "message matched regex profile (/$sThisRegex/)");
                    return "profile:" . $rFilterRegexProfile{$iRegexFilterID}->{title};
                }
            }
        }
    }

    # check for a previously seen message in a room with ack-mode enabled
    if ($iRoom && $g_hRooms{$iRoom}->{ack_mode}) {
        my $sGenericMessage = $sMessage;
        $sGenericMessage =~ s/\bDate(\/Time)*:\s*.*$//s;    # wipe Date to end of message
        $sGenericMessage =~ s/HTTP OK:.*\d+ by.*$//s;       # wipe HTTP OK to end of message
        $sGenericMessage =~ s/([()])/\\$1/g;                # escape any parens
        $sGenericMessage =~ s/\n|\r/ /g;                    # convert CR and linefeeds to spaces
        $sGenericMessage =~ s/\s{2,}/ /g;                   # consolidate multiple spaces to a single one
        $sGenericMessage =~ s/(^\s)|(\s$)//g;               # drop leading/trailing spaces

        foreach my $sPrevMsg (@{ $g_hRooms{$iRoom}->{history} }) {
            my $sLocalMsg = $sPrevMsg;
            $sLocalMsg =~ s/\n|\r/ /g;                    # convert CR and linefeeds to spaces
            $sLocalMsg =~ s/\s{2,}/ /g;                   # consolidate multiple spaces to a single one
            $sLocalMsg =~ s/(^\s)|(\s$)//g;               # drop leading/trailing spaces

            debugLog(D_filters, "ack check [$sLocalMsg] against [$sGenericMessage]");
            if ($sLocalMsg =~ /$sGenericMessage/) {
                debugLog(D_filters, "message matched previous in room's history (ack-mode)");
                return "ackMode";
            }
        }
    }

    # nothing matched / nothing blocked
    return 0;
}



sub setRecoveryLoadFilterTill($) {
    my $iTill = shift;
    $iFilterRecoveryLoadTill = $iTill;
}



sub setAllNagiosFilterTill($) {
    my $iTill = shift;
    $iFilterAllNagiosTill = $iTill;
}

sub getAllNagiosFilterTill() {return $iFilterAllNagiosTill;}

sub getRecoveryLoadFilterTill() {return $iFilterRecoveryLoadTill;}



sub newRegexFilter($$) {
    my ($sRegex, $iTill) = @_;
    my $iLastID = 1;

    # if the regex matches an existing one, we'll use the same ID and update that one's expiration
    # time.  otherwise we find the next available ID
    foreach my $iRegexFilterID (sort keys %rFilterRegex) {
        $iLastID = $iRegexFilterID;
        last if ($sRegex eq $rFilterRegex{$iRegexFilterID}->{regex});
        $iLastID++;
    }

    debugLog(D_filters, (defined $rFilterRegex{$iLastID} ? 'updated' : 'added') . " RegexFilter /$sRegex/ (id $iLastID)");
    $rFilterRegex{$iLastID} = { regex => $sRegex, till => $iTill };
}



sub rmRegexFilter($) {
    my $sRegex = shift;

    foreach my $iRegexFilterID (keys %rFilterRegex) {
        if ($rFilterRegex{$iRegexFilterID}->{regex} eq $sRegex) {
            debugLog(D_filters, "removed " . $rFilterRegex{$iRegexFilterID}->{regex} . " (id $iRegexFilterID)");
            delete $rFilterRegex{$iRegexFilterID};
            return 1;
        }
    }

    return 0;
}


sub newRegexProfile($$$$) {
    my ($sTitle, $sRegex, $sFrom, $sTill) = @_;
    my $iLastID = 1;

    foreach my $iRegexProfileID (sort keys %rFilterRegexProfile) {
        $iLastID = $iRegexProfileID;
        last if ($sRegex eq $rFilterRegexProfile{$iRegexProfileID}->{regex});
        $iLastID++;
    }

    debugLog(D_filters, (defined $rFilterRegexProfile{$iLastID} ? 'updated' : 'added') . " regex profile /$sRegex/ from $sFrom to $sTill ($sTitle)");
    $rFilterRegexProfile{$iLastID} = { title => $sTitle, regex => $sRegex, from => $sFrom, till => $sTill };
}


sub profileStatus() {
    my $sResult = '';

    foreach my $iRegexProfileID (sort keys %rFilterRegexProfile) {
        $sResult = cr($sResult) . "  [" . $rFilterRegexProfile{$iRegexProfileID}->{from} . ' to ' . $rFilterRegexProfile{$iRegexProfileID}->{till} . "] " . $rFilterRegexProfile{$iRegexProfileID}->{title} . ", /" . $rFilterRegexProfile{$iRegexProfileID}->{regex} . "/";
    }

    return $sResult ? "Regex Profiles:\n$sResult" : '';
}


1;
