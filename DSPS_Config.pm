package DSPS_Config;

use Hash::Case::Preserve;
use Date::Parse;
use DSPS_User;
use DSPS_Room;
use DSPS_Alias;
use DSPS_Escalation;
use DSPS_CmdPermission;
use DSPS_Trigger;
use DSPS_Debug;
use strict;
use warnings;

use base 'Exporter';
our @EXPORT = ('%g_hConfigOptions', '%g_hConfigVias');

# set defaults
our %g_hConfigOptions = ('require_at' => 0);
our %g_hConfigVias;
our $sConfigPath = '/etc';

# these are the sys directives that can appear in the config file.
# the ones with 0 hash values take values (strings).
# the ones with 1 hash values take bools.
my %hSysDirectives = (
    'default_maint' => 0,
    'gateway_url' => 0,
    'gateway_params' => 0,
    'gateway_media_params' => 0,
    'gateway_auth' => 0,
    'desk_url' => 0,
    'desk_auth' => 0,
    'fallback_email' => 0,
    'nagios_recovery_regex' => 0,
    'dsps_server' => 0,
    'smtp_server' => 0,
    'server_listen' => 0,
    'smtp_from' => 0,
    'admin_email' => 0,
    'rt_connection' => 0,
    'override_user' => 0,
    'subscription_prefix' => 0,
    'override_regex'  => 0,
    'rt_link' => 0,
    'log_rooms_to'  => 0,
    'nagios_problem_regex' => 0,
    'nagios_acknowledgement_regex' => 0,
    'http_auth' => 0,
    'summary_text' => 0,
    'subscriptions' => 0,
    'subscription_gateway_params' => 0,

    'show_nonhuman' => 1, 
    'require_at' => 1, 
    'summary_reminder' => 1
);

tie my (%hSeenAliases), 'Hash::Case::Preserve';

sub checkAliasRecursion($);



sub checkAliasRecursion($) {
    my $sAlias = shift;

    $hSeenAliases{$sAlias} = 1;
    tie my (%hCaselessAliases), 'Hash::Case::Preserve';
    %hCaselessAliases = %g_hAliases;

    if (defined $hCaselessAliases{$sAlias}) {
        while ($hCaselessAliases{$sAlias}->{referent} =~ m,(\w+),g) {
            my $sThisReferent = $1;

            if (defined $hCaselessAliases{$sThisReferent}) {
                return "$sThisReferent recursively used in $sAlias" if (defined $hSeenAliases{$sThisReferent});

                my $sError = checkAliasRecursion($sThisReferent);
                return $sError if $sError;
            }
        }
    }

    return '';
}



sub configSyntaxValid() {
    my $bValid = 1;
    my $bAt    = $g_hConfigOptions{require_at};

    # per user checks
    foreach my $iPhone (keys %g_hUsers) {
        unless (length($iPhone) == 10) {
            print STDERR infoLog('user ' . $g_hUsers{$iPhone}->{name} . ' of ' . $g_hUsers{$iPhone}->{group} . "doesn't have a 10 digit phone number");
            $bValid = 0;
        }

        unless ($g_hUsers{$iPhone}->{name} =~ /$g_hUsers{$iPhone}->{regex}/i) {
            print STDERR infoLog('user ' . $g_hUsers{$iPhone}->{name} . "'s \"name\" isn't contained in their \"regex\"; this is an internal DSPS requirement");
            $bValid = 0;
        }

        if ($g_hUsers{$iPhone}->{regex} =~ /^\s*$/) {
            print STDERR infoLog('user ' . $g_hUsers{$iPhone}->{name} . " ($iPhone) has a blank regex");
            $bValid = 0;
        }

        if ($bAt && defined($g_hUsers{$iPhone}->{auto_include})) {
            foreach my $sReference (split(/[ ,;:]+/, $g_hUsers{$iPhone}->{auto_include})) {
                unless ($sReference =~ /^\@/) {
                    print STDERR infoLog("WARNING: user " . $g_hUsers{$iPhone}->{name} . "'s redirect includes $sReference without leading @ (with require_at:true)");
                }
            }
        }
    }

    # per escalation checks
    foreach my $sEscName (keys %g_hEscalations) {
        if ($g_hEscalations{$sEscName}->{timer} && !$g_hEscalations{$sEscName}->{escalate_to}) {
            print STDERR infoLog("escalation $sEscName has a timer defined but no escalate_to");
            $bValid = 0;
        }

        if (!$g_hEscalations{$sEscName}->{timer} && $g_hEscalations{$sEscName}->{escalate_to}) {
            print STDERR infoLog("escalation $sEscName has an escalate_to defined but no timer");
            $bValid = 0;
        }

        if ($bAt) {
            foreach my $sReference (split(/[ ,;:]+/, $g_hEscalations{$sEscName}->{escalate_to})) {
                unless ($sReference =~ /^\@/) {
                    print STDERR infoLog("WARNING: escalation ${sEscName}'s escalate_to includes $sReference without leading @ (with require_at:true)");
                }
            }
        }

        unless (DSPS_Escalation::getOncallPerson($sEscName)) {
            print STDERR infoLog("escalation $sEscName has no one currently on call (no dates defined or all dates in the future?)");
            $bValid = 0;
        }
    }

    # per alias check
    foreach my $sAlias (keys %g_hAliases) {

        %hSeenAliases = ();
        my $sError = checkAliasRecursion($sAlias);
        if ($sError) {
            print STDERR infoLog("Alias error: $sError");
            $bValid = 0;
        }

        if ($bAt) {
            foreach my $sReference (split(/[ ,;:]+/, $g_hAliases{$sAlias}->{referent})) {
                unless ($sReference =~ /^\@/) {
                    print STDERR infoLog("WARNING: alias $sAlias includes $sReference without leading @ (with require_at:true)");
                }
            }
        }

    }

    # per trigger check
    foreach my $sTrig (keys %g_hTriggers) {
        unless (defined($g_hTriggers{$sTrig}->{name}) && $g_hTriggers{$sTrig}->{name}) {
            print STDERR infoLog("trigger defined with no name");
            $bValid = 0;
        }

        unless (defined($g_hTriggers{$sTrig}->{message_to_users}) && $g_hTriggers{$sTrig}->{message_to_users}) {
            print STDERR infoLog("trigger $sTrig is missing a trig_message");
            $bValid = 0;
        }

        unless (defined($g_hTriggers{$sTrig}->{event_match_string}) && $g_hTriggers{$sTrig}->{event_match_string}) {
            print STDERR infoLog("trigger $sTrig is missing a trig_regex");
            $bValid = 0;
        }

        unless (defined($g_hTriggers{$sTrig}->{command}) && $g_hTriggers{$sTrig}->{command}) {
            print STDERR infoLog("trigger $sTrig is missing a trig_command");
            $bValid = 0;
        }

        unless (defined($g_hTriggers{$sTrig}->{required_user}) && $g_hTriggers{$sTrig}->{required_user}) {
            print STDERR infoLog("trigger $sTrig is missing a trig_user");
            $bValid = 0;
        }
    }

    # sys lines checks
    if ($bAt && $g_hConfigOptions{default_maint}) {
        foreach my $sReference (split(/[ ,;:]+/, $g_hConfigOptions{default_maint})) {
            unless ($sReference =~ /^\@/) {
                print STDERR infoLog("WARNING: sys:default_maint includes $sReference without leading @ (with require_at:true)");
            }
        }
    }

    return $bValid;
}



sub readConfig(;$) {
    my $sConfigFileName = shift || "$sConfigPath/dsps.conf";

    unless (open(CFG, $sConfigFileName)) {
        print infoLog("Unable to read $sConfigFileName");
        return 0;
    }

    debugLog(D_configRead, "parsing $sConfigFileName");

    my $sSection = '';
    my $sInfo    = '';
    my $iErrors  = 0;
    my $rStruct  = 0;
    my $iLine    = 0;
    my $iRegexNum = 0;

  LINE: while (<CFG>) {
        ++$iLine;
        my $sLineNum = "[$sConfigFileName line $iLine]";

        chomp();
        s/^\s*(.*)\s*/$1/;

        # ignore blank lines & comments
        next if /^\s*$/;
        next if /^\s*#/;
        s/\s*#.*$//;

        # group tag
        if (/\bgroup\s*:\s*(\S*)/i) {
            $sInfo    = $1;
            $sSection = 'group';

            unless ($sInfo) {
                print infoLog("configuration error - 'group:' must be followed by a name $sLineNum");
                ++$iErrors;
            }
            next;
        }

        # group: user line
        if (/\b(?:u|user)\s*:\s*(.*)/i) {
            my $sLine  = $1;
            my $sGroup = $sInfo;

            if ($sSection eq 'group') {
                my @aData = split(/\s*,\s*/, $sLine);

                if (defined $g_hUsers{ $aData[2] }) {
                    print infoLog("configuration error - user with phone number " . $aData[2] . " defined twice (" . $g_hUsers{ $aData[2] }->{name} . ' & ' . $aData[0] . ") $sLineNum");
                    ++$iErrors;
                    next;
                }

                unless ($aData[2] =~ /^\s*\d+\s*$/) {
                    if ($aData[2] =~ /^\s*[\d\(\)-]+\s*$/) {
                        print infoLog("configuration error - user's phone number needs to be digits only, no punctuation $sLineNum");
                    }
                    else {
                        print infoLog("configuration error - user has an invalid phone number (should be 10 digits) $sLineNum");
                    }
                    ++$iErrors;
                    next;
                }

                unless ($aData[3] =~ /^\s*\d+\s*$/) {
                    print infoLog("configuration error - user " . $aData[0] . " (" . $aData[2] . ") doesn't have a valid (numeric) permission level $sLineNum");
                    ++$iErrors;
                    next;
                }

                my $rUser = DSPS_User::createUser($aData[0], $aData[1], $aData[2], $sGroup, $aData[3]);

                # user options
                if ($#aData > 3) {
                    for my $iField (4 .. ($#aData)) {
                        if (defined $aData[$iField] && $aData[$iField]) {

                            if ($aData[$iField] =~ /redirect\s*:\s*(.*)/i) {
                                $rUser->{auto_include} = $1;
                            }
                            elsif ($aData[$iField] =~ /via\s*:\s*(.*)/i) {
                                $rUser->{via} = $1;
                            }
                            elsif ($aData[$iField] =~ /valid\s*:\s*(.*)/i) {
                                if (my $iTime = str2time($1)) {
                                    # the original config info will be a date which means we'll end up with epoch seconds
                                    # equal to midnight at the *start* of the person's last valid day.  so they'll get
                                    # taken out a day early.  let's push it back to 3pm that afternoon by adding 15 hours.
                                    $rUser->{valid_end} = $iTime + 54000;
                                }
                                else {
                                    print infoLog("configuration error - user has an invalid date for the 'valid' option: $sLine $sLineNum");
                                    ++$iErrors;
                                }
                            }
                            else {
                                print infoLog("configuration error - user has an invalid option: $sLine $sLineNum");
                                ++$iErrors;
                            }
                        }
                    }
                }
            }
            else {
                print infoLog("configuration error - user not part of valid group: $sLine $sLineNum");
                ++$iErrors;
            }
            next;
        }

        # trigger tag
        if (/\btrigger\s*:\s*(.*)$/i) {
            $sInfo    = $1;
            $sSection = 'trigger';

            if ($sInfo) {
                $rStruct = DSPS_Trigger::createOrReplaceTrigger($sInfo);
            }
            else {
                print infoLog("configuration error - 'trigger:' must be followed by a name $sLineNum");
                ++$iErrors;
            }
            next;
        }

        # trigger regex
        if (/\b(?:trig_regex)\s*:\s*\/*(.+?)\/*\s*$/i) {
            my $iValue = $1;

            if ($sSection eq 'trigger') {
                $rStruct->{event_match_string} = $iValue;
            }
            else {
                print infoLog("configuration error - regex not part of a valid trigger: trig_regex:$iValue $sLineNum");
                ++$iErrors;
            }
            next;
        }

        # trigger message
        if (/\b(?:trig_message)\s*:\s*(.+)/i) {
            my $iValue = $1;

            if ($sSection eq 'trigger') {
                $rStruct->{message_to_users} = $iValue;
            }
            else {
                print infoLog("configuration error - message not part of a valid trigger: message_to_users:$iValue $sLineNum");
                ++$iErrors;
            }
            next;
        }

        # trigger user
        if (/\b(?:trig_user)\s*:\s*(.+)/i) {
            my $iValue = $1;

            if ($sSection eq 'trigger') {
                $rStruct->{required_user} = $iValue;
            }
            else {
                print infoLog("configuration error - user not part of a valid trigger: trig_user:$iValue $sLineNum");
                ++$iErrors;
            }
            next;
        }

        # trigger command
        if (/\b(?:trig_command)\s*:\s*(.+)/i) {
            my $iValue = $1;

            if ($sSection eq 'trigger') {
                $rStruct->{command} = $iValue;
            }
            else {
                print infoLog("configuration error - command not part of a valid trigger: trig_command:$iValue $sLineNum");
                ++$iErrors;
            }
            next;
        }

        # alias tag
        if (/\balias\s*:\s*(\S*)/i) {
            $sInfo    = $1;
            $sSection = 'alias';

            if ($sInfo) {
                $rStruct = DSPS_Alias::createAlias($sInfo);
            }
            else {
                print infoLog("configuration error - 'alias:' must be followed by a name $sLineNum");
                ++$iErrors;
            }
            next;
        }

        # alias referent
        if (/\b(?:r|referent)\s*:\s*(.+)/i) {
            my $iValue = $1;

            if ($sSection eq 'alias') {
                $rStruct->{referent} = $iValue;
            }
            else {
                print infoLog("configuration error - referent not part of a valid alias: r:$iValue $sLineNum");
                ++$iErrors;
            }
            next;
        }

        # options
        if (/\b(?:o|option[s]*)\s*:\s*(.+)/i) {
            my $iValue = $1;

            if ($sSection eq 'alias') {
                while ($iValue =~ m,(\w+),g) {
                    my $sAnOption = $1;
                    if ($sAnOption =~ /hidden/i) {
                        $rStruct->{hidden} = 1;
                    }
                    elsif ($sAnOption =~ /broadcast/i) {
                        $rStruct->{broadcast} = 1;
                    }
                    else {
                        print infoLog("configuration error - unrecognized alias option: o:$sAnOption $sLineNum");
                        ++$iErrors;
                    }
                }
            }
            elsif ($sSection eq 'escalation') {
                if ($iValue =~ /rt_queue\s*[:=]*\s*(.*)/i) {
                    $rStruct->{rt_queue} = $1;
                }
                elsif ($iValue =~ /rt_subject\s*[:=]*\s*(.*)/i) {
                    $rStruct->{rt_subject} = $1;
                }
                elsif ($iValue =~ /desk_priority\s*[:=]*\s*(.*)/i) {
                    $rStruct->{desk_priority} = $1;
                }
                else {
                    print infoLog("configuration error - unrecognized escalation option: o:$iValue $sLineNum");
                    ++$iErrors;
                }
            }
            else {
                print infoLog("configuration error - options not part of a valid alias or escalation: o:$iValue $sLineNum");
                ++$iErrors;
            }
            next;
        }

        # via definition
        if (/\bvia\s*:\s*(\S+)\s*[,:;=\s]+(\S+)/i) {
            my $sName = $1;
            my $sValue = $2;
            $sSection = '';

            if ($sValue !~ /\./) {
                print infoLog("configuration error - 'via' definition should be a valid email address domain $sLineNum");
                ++$iErrors;
            }
            else {
                $g_hConfigVias{$sName} = $sValue;
            }

            next;
        }

        # swap email
        if (/\b(?:se|swap_email)\s*:\s*(.+)/i) {
            my $sValue = $1;

            if ($sSection eq 'escalation') {
                $rStruct->{swap_email} = $sValue;
            }
            else {
                print infoLog("configuration error - swap email outside of escalation: se:$sValue $sLineNum");
                ++$iErrors;
            }
            next;
        }

        # cancel message
        if (/\b(?:cm|cancel_message|cancel_msg)\s*:\s*(.+)/i) {
            my $sValue = $1;

            if ($sSection eq 'escalation') {
                $rStruct->{cancel_msg} = $sValue;
            }
            else {
                print infoLog("configuration error - cancel message outside of escalation: cancel_msg:$sValue $sLineNum");
                ++$iErrors;
            }
            next;
        }

        # minimum people to abort
        if (/\b(?:min_to_abort|min_people_to_abort|minimum_people_to_abort)\s*:\s*(\d+)/i) {
            my $iValue = $1;

            if ($sSection eq 'escalation') {
                $rStruct->{min_to_abort} = $iValue;
            }
            else {
                print infoLog("configuration error - min_to_abort outside of escalation $sLineNum");
                ++$iErrors;
            }
            next;
        }

        # alert_subject
        if (/\b(?:as|alert_subject)\s*:\s*(.+)/i) {
            my $sValue = $1;

            if ($sSection eq 'escalation') {
                $rStruct->{alert_subject} = $sValue;
            }
            else {
                print infoLog("configuration error - alert subject outside of escalation: as:$sValue $sLineNum");
                ++$iErrors;
            }
            next;
        }

        # alert email
        if (/\b(?:ae|alert_email)\s*:\s*(.+)/i) {
            my $sValue = $1;

            if ($sSection eq 'escalation') {
                $rStruct->{alert_email} = $sValue;
            }
            else {
                print infoLog("configuration error - alert email outside of escalation: ae:$sValue $sLineNum");
                ++$iErrors;
            }
            next;
        }

        # escalation tag
        if (/\bescalation\s*:\s*(\S*)/i) {
            $sInfo    = $1;
            $sSection = 'escalation';

            if ($sInfo) {
                $rStruct = DSPS_Escalation::createEscalation($sInfo);
            }
            else {
                print infoLog("configuration error - 'escalation:' must be followed by a name $sLineNum");
                ++$iErrors;
            }
            next;
        }

        # escalation: t: line
        if (/\b(?:t|timer)\s*:\s*(\d+)/i) {
            my $iValue = $1;

            if ($sSection eq 'escalation') {
                $rStruct->{timer} = $iValue;
            }
            else {
                print infoLog("configuration error - timer not part of a valid escalation: t:$iValue $sLineNum");
                ++$iErrors;
            }
            next;
        }

        # escalation: e: line
        if (/\b(?:e|escalate_to)\s*:\s*(.+)/i) {
            my $iValue = $1;

            if ($sSection eq 'escalation') {
                $rStruct->{escalate_to} = $iValue;
            }
            else {
                print infoLog("configuration error - escalate_to not part of a valid escalation: e:$iValue $sLineNum");
                ++$iErrors;
            }
            next;
        }

        # escalation: s: line
        if (/\b(?:s|sched|schedule)\s*:\s*(\d{8})\W+(.+)$/i) {
            my $sDate               = $1;
            my $sSched              = $2;
            my $iStartingErrorCount = $iErrors;

            if ($sSection eq 'escalation') {

                if ($sSched =~ /^auto\b(?:\W*)(.*)/i) {
                    my $sPeople = $1;

                    while ($sPeople =~ m,(\w+),g) {
                        my $sPerson = $1;
                        unless (DSPS_User::matchUserByRegex($sPerson)) {
                            print infoLog("configuration error - " . $rStruct->{name} . " schedule $sDate references undefined person $sPerson $sLineNum");
                            ++$iErrors;
                        }
                    }
                }
                elsif ($sSched =~ /^\s*(\w+)\s*$/) {
                    my $sPerson = $1;

                    unless (DSPS_User::matchUserByRegex($sPerson)) {
                        print infoLog("configuration error - " . $rStruct->{name} . " schedule $sDate references undefined person $sPerson $sLineNum");
                        ++$iErrors;
                    }
                }
                else {
                    print infoLog("configuration error - " . $rStruct->{name} . " schedule $sDate should list a single person's name (unless using 'auto') $sLineNum");
                    ++$iErrors;
                }

                if ($iStartingErrorCount == $iErrors) {
                    my %hSchedule = %{ $rStruct->{schedule} };
                    $hSchedule{$sDate} = $sSched;
                    $rStruct->{schedule} = \%hSchedule;
                    debugLog(D_configRead, "adding " . $rStruct->{name} . " $sDate schedule as $sSched (now " . keys(%hSchedule) . " entries) $sLineNum");
                }
            }
            else {
                print infoLog("configuration error - schedule not part of a valid escalation: s: $sDate $sLineNum");
                ++$iErrors;
            }
            next;
        }

        # command permission line
        if (/\b(?:cmd|command)\s*:\s*([?:]\w+)\D+(\d+)/i) {
            my $sCmd   = $1;
            my $iValue = $2;

            if (defined $DSPS_CmdPermission::hDefaultCmdPermission{$sCmd}) {
                $DSPS_CmdPermission::hCmdPermission{$1} = $2;
            }
            else {
                print infoLog("configuration error - '$sCmd' isn't a valid command $sLineNum");
                ++$iErrors;
            }
            next;
        }

        # ambiguous names lines
        if (/\b(?:amb|ambiguous)\s*:\s*([-|\w]+)[,;:\s]+(.+)/i) {
            $DSPS_User::g_hAmbigNames{$1} = $2;
            next;
        }

        # general configuration sys: line
        if (/\b(?:sys|system)\s*:\s*([^:]+)\s*:\s*(.+)/i) {
            my $sOption = $1;
            my $sValue  = $2;

            # these are bool directives
            if (defined ($hSysDirectives{$sOption}) && $hSysDirectives{$sOption}) {
                $g_hConfigOptions{$sOption} = ($sValue =~ /y|t|1|enable|on/i ? 1 : 0);
                next LINE;
            }
            # these are value directives
            elsif (defined ($hSysDirectives{$sOption})) {
                $sValue =~ s/^\s*\/(.*?)\/\s*$/$1/;
                $g_hConfigOptions{$sOption} = $sValue;
                next LINE;
            }
        }

        # regex substitution line
	if (/\b(?:regex_subst)\s*:\s*\/(.*[^\\])\/(.*?)\/$/i) {
            $g_hConfigOptions{regex_subst}{$1} = $2;
	    push(@{$g_hConfigOptions{regex_subst_order}}, $1);
	    debugLog(D_configRead, "regex_subst $1 --> $2\n");
            next;
        }

        # regex profile line
        if (/\b(?:profile|regex_profile)\s*:\s*["']*([^,;]+?)["']*\s*[,;]\s*\/([^\/]+)\/\s*[,;]\s*(\d{1,2}:\d{2})\s*[,;]\s*(\d{1,2}:\d{2})/i) {
            my $sTitle = $1;
            my $sRegex = $2;
            my $sFrom = $3;
            my $sTill = $4;
            DSPS_SystemFilter::newRegexProfile($sTitle, $sRegex, $sFrom, $sTill);
            next;
        }

        print infoLog("configuration error - unknown directive: \"$_\" $sLineNum");
        ++$iErrors;
    }

    debugLog(D_configRead, "escalations loaded: " . join(', ', sort keys %g_hEscalations)) if (keys %g_hEscalations);

    close(CFG);
    return (!$iErrors);
}



sub writeConfig() {
    my $sConfigFileName = shift || "$sConfigPath/dsps.conf";

    # is the config file a symlink?
    my $sRealFile = $sConfigFileName;
    eval {
        if (-l $sConfigFileName) {
            $sRealFile = readlink($sConfigFileName);
            unless ($sRealFile =~ m,^/,) {
                my $sDir = $sConfigFileName;
                print "pre=$sDir\n";
                $sDir =~ s/(.*)\/.*$/$1/;
                print "post=$sDir\n";
                $sRealFile = "$sDir/$sRealFile";
            }
        }
    };
    $sConfigFileName = $sRealFile;

    open(CFG, $sConfigFileName)      || return 0;
    open(NEW, ">${sConfigFileName}.new") || return infoLog("Unable to write new config file (${sConfigFileName}.new)");
    debugLog(D_configWrite, "rewriting config file ($sConfigFileName)");

    my $sSection       = '';
    my $sInfo          = '';
    my $bFoundSchedule = 0;
    my $sIndent        = '';

    while (<CFG>) {
        chomp();
        my $sOrigLine = $_;

        # s/^\s*(.*)\s*/$1/;
        s/\s*#.*$//;

        if (/\b(?:u|user)\s*:\s*(.*)/i) {
            my $sLine  = $1;
            my @aData = split(/\s*,\s*/, $sLine);

	    if (!defined $g_hUsers{$aData[2]}) {
		debugLog(D_configWrite, "  - removing user " . $aData[0]);
		if ($sOrigLine = ~ /^(\s*)(.*)$/) {
		    $sOrigLine = "$1# $2";
		}
	    } 
	}

        if (/^(\s*)([teso]|timer|escalate_to|alert_email|as|ae|alert_subject|min_to_abort|min_people_to_abort|minimum_people_to_abort|swap_email|cancel_msg|options|schedule|sched)\s*:/i) {
            $sIndent = $1;
        }
        else {
            $sSection = '' if /:/;
        }

        if (/^\s*escalation\s*:\s*(\S+)/i) {
            $sSection       = 'escalation';
            $sInfo          = $1;
            $bFoundSchedule = 0;
        }

        if (($sSection eq 'escalation') && /^\s*(s|sched|schedule)\s*:/i && defined($g_hEscalations{$sInfo})) {

            unless ($bFoundSchedule) {
                debugLog(D_configWrite, "  - rewriting schedule for escalation $sInfo");
                my %hSchedule = %{ $g_hEscalations{$sInfo}->{schedule} };
                foreach my $sDate (sort keys %hSchedule) {
                    print NEW "${sIndent}s:$sDate " . $hSchedule{$sDate} . "\n";
                }
            }

            $bFoundSchedule = 1;
            next;
        }

        print NEW "$sOrigLine\n";
    }

    close(CFG);
    close(NEW);

    # backup the config file
    # this can fail if we don't have write access to the dir in question (like /etc)
    # no point in checking for failure since there's little else to do
    unlink("$sConfigFileName.bck");
    rename("$sConfigFileName", "$sConfigFileName.bck");

    if (rename("${sConfigFileName}.new", $sConfigFileName)) {
        debugLog(D_configWrite, "saved new configuration file $sConfigFileName");
        return '';
    }
    else {
        return infoLog("Unable to rename new configuration file into place ($sConfigFileName)");
    }
}

1;
