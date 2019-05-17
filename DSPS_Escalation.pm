package DSPS_Escalation;

use Date::Parse;
use Date::Format;
use DSPS_User;
use DSPS_Room;
use DSPS_String;
use DSPS_Util;
use DSPS_Debug;
use strict;
use warnings;

use base 'Exporter';
our @EXPORT = ('%g_hEscalations');

our %g_hEscalations;



sub createEscalation {
    my $rhEsc = {
        name          => $_[0],
        timer         => $_[1] || 300,
        escalate_to   => $_[2] || '',
        rt_queue      => $_[3] || '',
        rt_subject    => '',
        min_to_abort  => 2,
        cancel_msg    => '',
        schedule      => {},
        alert_subject => '',
        alert_email   => '',
    };

    $g_hEscalations{ $_[0] } = $rhEsc;
}


sub dropUserFromAllEscalations($) {     # requires user to still be defined at this point
    my $iUser = shift;

    foreach my $sEscName (keys %g_hEscalations) {
	my $sStartingOncall = getOncallPerson($sEscName);
        my %hSchedule = %{ $g_hEscalations{$sEscName}->{schedule} };

	foreach my $sSchedDate (keys %hSchedule) {
	    my $sSchedLine = $hSchedule{$sSchedDate};

	    if ($sSchedLine =~ /^auto/i) {
                my @aOnCallNames = ();

		my $bAutoChanged = 0;
                while ($sSchedLine =~ m,(\w+),g) {
                    next if ($1 =~ /^auto$/i);
                    my $sSchedPerson = $1;
                    my $iPhone = DSPS_User::matchUserByRegex($sSchedPerson);

		    if (defined($iPhone) && $iPhone != $iUser) {
                        push(@aOnCallNames, $sSchedPerson);
		    }
		    else {
			$bAutoChanged = 1;
			debugLog(D_escalations, "dropping $iUser from $sEscName ($sSchedDate)");
		    }
                }

		if ($bAutoChanged) {
		    $hSchedule{$sSchedDate} = 'auto/' . join(',', @aOnCallNames);
		}
	    }
	    else {
		my $iNamedUsersPhone = DSPS_User::matchUserByRegex($sSchedLine);

		if ($iNamedUsersPhone == $iUser) {
		    delete($hSchedule{$sSchedDate});
		}
	    }
	}

        $g_hEscalations{$sEscName}->{schedule} = \%hSchedule;
	my $sEndingOncall = getOncallPerson($sEscName);

	if ($sStartingOncall ne $sEndingOncall) {
	    debugLog(D_escalations, "new on call person for $sEscName is $sEndingOncall");
            main::sendEmail($g_hEscalations{$sEscName}->{swap_email}, main::getAdminEmail(), 
	      sv(E_OnCallDueToInvalidating4, $sEscName, $g_hUsers{$iUser}->{name}, $sEscName, $sEndingOncall));
	}
    }
}


sub primeEscalation($$$) {
    my ($sSender, $sEscName, $sMessage) = @_;
    my $iOncallPhone = getOncallPerson($sEscName);

    # put the oncall peson in a room with the sender
    my $bRoomChanged = DSPS_Room::combinePeoplesRooms($g_hUsers{$sSender}, $g_hUsers{$iOncallPhone});
    my $iRoom = DSPS_Room::findUsersRoom($iOncallPhone);

    # never prime an escalation off of a recovery page
    return $bRoomChanged if (main::getRecoveryRegex() && $sMessage =~ main::getRecoveryRegex());

    # are there enough other people in the room to skip the escalation?
    my $iOccupants = () = DSPS_Room::roomStatusIndividual($iRoom, 1, 1);
    if ($iOccupants >= $g_hEscalations{$sEscName}->{min_to_abort}) {
        debugLog(D_escalations, $g_hUsers{$iOncallPhone}->{name} . " is already in room $iRoom which has $iOccupants people" . " - aborting $sEscName escalation");
        return $bRoomChanged;
    }

    # is the sending user human?  if so we've already pulled the person in, so we're done.  we don't want to start an escalation timer for a human
    return $bRoomChanged if (DSPS_User::humanUsersPhone($sSender));

    # is an escalation already in progress in this room?
    if ($g_hRooms{$iRoom}->{escalation_time}) {
        debugLog(D_escalations, $g_hUsers{$iOncallPhone}->{name} . " is in room $iRoom which already has an escalation timer in progress - won't reset");
        return $bRoomChanged;
    }

    # did the on call person in the room respond within the last 20 minutes?  if so we're not going to prime another escalation
    # this is primiarly to catch flapping nagios issues where the on call person is constantly having to disarm escalations
    if ($g_hRooms{$iRoom}->{last_human_reply_time} >= $main::g_iLastWakeTime - 1200) {
        debugLog(D_escalations, $g_hUsers{$iOncallPhone}->{name} . " has responded within the last 20 minutes;  not rearming the escalation");
        return $bRoomChanged;
    }

    # calculate the initial timer offset which will ideally be 2 minutes less than the admin configured in the conf file.
    # that allows us to do a resend 2 minutes before expiration and then another one 1 minute before to give the on call
    # person a total of 3 attempts before we escalate to the wider audience.  if the initially configured timer is less than 3
    # minutes then we get to do fewer retries before escalation.  the offset, encoded as a decimal portion, says how many retries
    # to do;  they're read/used in checkEscalationTimes().
    my $iOffset = $g_hEscalations{$sEscName}->{timer} > 179 ? 2 : $g_hEscalations{$sEscName}->{timer} > 119 ? 1 : 0;

    # it's a go - setup the escalation
    # the -2 is to offset race conditions so we don't miss a full sleep/select cycle in the main loop
    $g_hRooms{$iRoom}->{escalation_time}        = ($main::g_iLastWakeTime + $g_hEscalations{$sEscName}->{timer} - (60 * $iOffset) - 2) . ($iOffset ? ".$iOffset" : '');
    $g_hRooms{$iRoom}->{escalation_to}          = $g_hEscalations{$sEscName}->{escalate_to};
    $g_hRooms{$iRoom}->{escalation_orig_sender} = $sSender;
    $g_hRooms{$iRoom}->{escalation_name}        = $sEscName;

    # do we need to create an RT ticket?
    if ($g_hEscalations{$sEscName}->{rt_queue}) {
        $g_hRooms{$iRoom}->{ticket_number} = main::rtCreateTicket(
            $sMessage,
            $g_hEscalations{$sEscName}->{rt_queue},
            defined($g_hEscalations{$sEscName}->{rt_subject}) ? $g_hEscalations{$sEscName}->{rt_subject} : 'DSPS Ticket'
        );
    }

    # do we need to create a Desk.com case?
    if ($g_hEscalations{$sEscName}->{desk_priority}) {
        $g_hRooms{$iRoom}->{ticket_number} = main::deskComCreateCase($sMessage, $g_hEscalations{$sEscName}->{desk_priority});
    }

    # send out an alert email if configured
    if ($g_hEscalations{$sEscName}->{alert_email}) {
        my $sAlertSuffix = '';

        if ($g_hEscalations{$sEscName}->{rt_queue}) {
            $sAlertSuffix = "\n\n----\nThis event is being tracked in RT ticket #" . $g_hRooms{$iRoom}->{ticket_number} . "\n" . (main::getRTLink() ? main::getRTLink() . $g_hRooms{$iRoom}->{ticket_number} : '');
        }
        elsif ($g_hEscalations{$sEscName}->{desk_priority}) {
            $sAlertSuffix = "\n\n----\nThis event is being tracked in Desk.Com case #" . $g_hRooms{$iRoom}->{ticket_number} . "\n";
        }

        my $sSubject = $g_hEscalations{$sEscName}->{alert_subject} ? $g_hEscalations{$sEscName}->{alert_subject} : 'DSPS Escalation!';
        main::sendEmail($g_hEscalations{$sEscName}->{alert_email}, '', sv(E_EscalationPrep3, $sSubject, $sEscName, main::messagePostFixUp($sMessage)) . $sAlertSuffix);
    }

    debugLog(D_escalations,
            "escalation timer of "
          . $g_hEscalations{$sEscName}->{timer}
          . " seconds started for room $iRoom via $sEscName ("
          . $g_hUsers{$iOncallPhone}->{name} . ' -> '
          . $g_hRooms{$iRoom}->{escalation_to}
          . ")");

    return $bRoomChanged;
}



sub getScheduledOncallPerson($;$) {
    my $sEscName = shift;
    my $iPlusDays = shift || 0;

    debugLog(D_escalations, "plusdays=$iPlusDays, name=$sEscName, defined: " . (defined $g_hEscalations{$sEscName}->{schedule} ? 1 : 0));
    return '' unless defined $g_hEscalations{$sEscName}->{schedule};

    my %hSchedule = %{ $g_hEscalations{$sEscName}->{schedule} };
    my ($iMinute, $iHour, $iDay, $iMonth, $iYear) = (localtime)[1 .. 5];
    my $iToday = sprintf("%d%02d%02d", $iYear + 1900, $iMonth + 1, $iDay);

    my $iPersonPhone;
    foreach my $sSchedLineDate (sort keys %hSchedule) {
        debugLog(D_escalations, "considering $sSchedLineDate");

        my $iTodayPlus = $iPlusDays ? time2str("%Y%m%d", (str2time(substr($iToday, 0, 8)) + (86400 * $iPlusDays))) : $iToday;

        if ($iTodayPlus > $sSchedLineDate || ($iTodayPlus == $sSchedLineDate && $iHour >= 12)) {

            if ($hSchedule{$sSchedLineDate} =~ /^auto/i) {
                my $sThisSched   = $hSchedule{$sSchedLineDate};
                my @aOnCallNames = ();

                while ($sThisSched =~ m,(\w+),g) {
                    next if ($1 =~ /^auto$/i);
                    my $sSchedPerson = $1;
                    my $iPhone       = DSPS_User::matchUserByRegex($sSchedPerson);
                    push(@aOnCallNames, $iPhone);
                }
                return '' if ($#aOnCallNames < 0);

                my $iDiff = sprintf("%.0f", (((86400 * $iPlusDays) + str2time(substr($iToday, 0, 8)) - str2time(substr($sSchedLineDate, 0, 8))) / 86400));
                debugLog(D_escalations, "iDiff = $iDiff using iPlusDays=$iPlusDays, today=$iToday, last sSchedLineDate=$sSchedLineDate");

                $iDiff-- if ($iHour < 12);
                $iPersonPhone = $aOnCallNames[int($iDiff / 7) % ($#aOnCallNames + 1)];
                last;
            }
            else {
                my $sEntry = $hSchedule{$sSchedLineDate};
                $iPersonPhone = DSPS_User::matchUserByRegex($sEntry);
            }
        }
        else {
            debugLog(D_escalations, "final was $sSchedLineDate");
            last;
        }
    }
    return $iPersonPhone;
}



sub getOncallPerson($;$) {
    my $sEscName  = shift;
    my $iPlusDays = shift || 0;
    my $iWeeks    = -1;
    my $iPhone;

    # lookup the oncall person for this particular escalation.  if that person is currently
    # on vacation we'll look another week into the future.  at most we go 3 weeks out before
    # giving up and in that case returning the on-vacation person anyway.
    #
    # here we use staycation synonymously with vacation, with no care for the current time
    # if you're on staycation you probably don't want to be on call
    do {
        $iPhone = getScheduledOncallPerson($sEscName, $iPlusDays + (++$iWeeks * 7));
        unless (defined $iPhone) {
            return '';
        }

    } while (((!defined $g_hUsers{$iPhone}) ||
              ($g_hUsers{$iPhone}->{vacation_end} > ($main::g_iLastWakeTime + (ONEWEEK * $iWeeks))) ||
              ($g_hUsers{$iPhone}->{staycation_end} > ($main::g_iLastWakeTime + (ONEWEEK * $iWeeks)))) 
               && ($iWeeks < 2));
              # "!defined user" can happen if the valid: directive is used on a user and they get removed
              # from the running config but are still in the escalation definition

    return $iPhone;
}



sub getFullOncallSchedule($) {
    my $sEscName = shift;

    return 'None.' unless defined $g_hEscalations{$sEscName}->{schedule};

    my $iWeeksShown = 0;
    my %hSchedule   = %{ $g_hEscalations{$sEscName}->{schedule} };
    my ($iMinute, $iHour, $iDay, $iMonth, $iYear) = (localtime)[1 .. 5];
    my $iToday        = sprintf("%d%02d%02d", $iYear + 1900, $iMonth + 1, $iDay);
    my $iTodaySeconds = str2time($iToday);
    my $sResult       = '';

    foreach (sort keys %hSchedule) {

        if (($hSchedule{$_} =~ /^auto/i) || ($iTodaySeconds) <= str2time($_) + 604000) {

            if ($hSchedule{$_} =~ /^auto/i) {
                my $sThisSched   = $hSchedule{$_};
                my @aOnCallNames = ();

                while ($sThisSched =~ m,(\w+),g) {
                    next if ($1 =~ /^auto$/i);
                    push(@aOnCallNames, DSPS_User::matchUserByRegex($1));
                }
                return 'None.' if ($#aOnCallNames < 0);

                my $iPlusWeek = -1;
                while (1) {
                    $iPlusWeek++;
                    my $iDiff = sprintf("%.0f", 7 * $iPlusWeek);
                    my $iPersonPhone = $aOnCallNames[int($iDiff / 7) % ($#aOnCallNames + 1)];
                    my $iNewDay = str2time($_) + ($iPlusWeek * ONEWEEK);

                    next unless ($iNewDay + 604000 >= $iTodaySeconds);
                    #print STDERR "getFullOncallSchedule() - $_ => " . str2time($_) . ", plusweek=$iPlusWeek; newDay=$iNewDay\n";

                    # the +3600 is to account for DST where we're an extra hour off.  because time2str("%x") is converting to a single day,
                    # the extra hour will push it further into the correct date.
                    $sResult .= time2str("%x", $iNewDay + 3600) . ": " . $g_hUsers{$iPersonPhone}->{name} . "\n";
                    $iWeeksShown++;

                    last if ($iWeeksShown > 4);
                }
                last;
            }
            else {
                my $sEntry       = $hSchedule{$_};
                my $iPersonPhone = DSPS_User::matchUserByRegex($sEntry);
                $sResult .= time2str("%x", str2time($_)) . ": " . $g_hUsers{$iPersonPhone}->{name} . "\n";
                $iWeeksShown++;
            }
        }
    }

    return $sResult;
}



sub checkEscalationCancel($$) {
    my ($iSender, $sMessage) = @_;
    my $iRoom = DSPS_Room::findUsersRoom($iSender);

    if ($iRoom && $g_hRooms{$iRoom}->{escalation_time}) {

        # we can cancel an escalation for this room if a human replied
        # or nagios sent a recovery/ack message
        if (DSPS_User::humanUsersPhone($iSender) || 
            (main::getRecoveryRegex() && $sMessage =~ main::getRecoveryRegex()) ||
            (main::getAckRegex() && $sMessage =~ main::getAckRegex())) {
            my $sEscName = $g_hRooms{$iRoom}->{escalation_name};

            $g_hRooms{$iRoom}->{escalation_time} = 0;
            $g_hRooms{$iRoom}->{escalation_to}   = '';
            $g_hRooms{$iRoom}->{escalation_name} = '';

            if (DSPS_User::humanUsersPhone($iSender)) {
                debugLog(D_escalations, "escalation for room $iRoom canceled by " . $g_hUsers{$iSender}->{name});
                main::sendSmsPage($iSender, t($g_hEscalations{$sEscName}->{cancel_msg}))
                  if (defined $g_hEscalations{$sEscName}) && ($g_hEscalations{$sEscName}->{cancel_msg});

            }
            else {
                debugLog(D_escalations, "escalation for room $iRoom canceled by recovery");
            }

            return 1;   # means we need to modify the message with a '-' prefix
        }
    }

    return 0;
}



sub checkEscalationTimes() {
    foreach my $iRoom (keys %g_hRooms) {

        # skip rooms with no escalation timer or where the timer hasn't expired yet
        next unless ($g_hRooms{$iRoom}->{escalation_time} && ($g_hRooms{$iRoom}->{escalation_time} <= $main::g_iLastWakeTime));

        my $sLastMessage = ${ $g_hRooms{$iRoom}->{history} }[$#{ $g_hRooms{$iRoom}->{history} }];
        unless ($sLastMessage) {
            infoLog("ERROR: escalation timer expired for room $iRoom but there's no history to send");
            next;
        }

        unless ($g_hRooms{$iRoom}->{escalation_orig_sender}) {
            infoLog("ERROR: escalation timer expired for room $iRoom but we don't know the original sender");
            next;
        }

        # our initial timer was internaly set to 1 or 2 minutes less than the admin configured it.  so at this point
        # we have a minute or two left before the real timer expires.  now we're going to re-send the initial page to give
        # the on call person another attempt before we actually escalate.  we distinguish between "timer expired
        # but we have this time left" and "real timer expired" by fudging the expiration time with a
        # decimal number.  if a decimal is in the expiration time, the decimal represents how many minutes are left.  no
        # decimal means its actually time to escalate.
        if ($g_hRooms{$iRoom}->{escalation_time} =~ /\.(\d)/) {
	    my $iDecimalValue = $1;
	    $iDecimalValue--;

            # extend the timer
            $g_hRooms{$iRoom}->{escalation_time} = $main::g_iLastWakeTime + 58 . ($iDecimalValue ? ".$iDecimalValue" : '');
	    debugLog(D_escalations, "escalation for room $iRoom courtesy resend (" . (($iDecimalValue + 1) * 60) . " seconds left)");

            # resend the initial page to the on call person
            main::sendUserMessageToRoom($g_hRooms{$iRoom}->{escalation_orig_sender}, $sLastMessage, 0);
            next;
        }

        debugLog(D_escalations, "escalation timer for room $iRoom has expired; firing escalation");

        # add the extra escalation people to the room
        main::processMentions($g_hRooms{$iRoom}->{escalation_orig_sender}, $g_hRooms{$iRoom}->{escalation_to}, $g_hRooms{$iRoom}->{escalation_to});

        my $sOrigSender  = $g_hRooms{$iRoom}->{escalation_orig_sender};
        my $sOrigEscName = $g_hRooms{$iRoom}->{escalation_name};
        my $sOrigTo      = $g_hRooms{$iRoom}->{escalation_to};

        # clear the escalation so it doesn't fire again
        # we do this before sendUserMessageToRoom() so that the sending function will know there's no more
        # pending escalation and therefore won't prepend a '+' to the message.
        # and we do it after the above processMentions() so it doesn't recursively setup another escalation - it will see this one in progress
        $g_hRooms{$iRoom}->{escalation_time} = 0;
        $g_hRooms{$iRoom}->{escalation_to}   = '';
        $g_hRooms{$iRoom}->{escalation_name} = '';

        # send out the pages
        main::sendUserMessageToRoom($sOrigSender, $sLastMessage, 'ESCALATED:');

        # send out a second email if configured
        if ($g_hEscalations{$sOrigEscName}->{alert_email}) {
            my $sRTSuffix =
                "\n\n----\nThis event is being tracked in RT ticket #"
              . $g_hRooms{$iRoom}->{ticket_number} . "\n"
              . (main::getRTLink() ? main::getRTLink() . $g_hRooms{$iRoom}->{ticket_number} : '');
            my $sSubject = ($g_hEscalations{$sOrigEscName}->{alert_subject} ? $g_hEscalations{$sOrigEscName}->{alert_subject} : 'DSPS Escalation!') . ' - ESCALATED!';

            main::sendEmail($g_hEscalations{$sOrigEscName}->{alert_email},
                '', sv(E_EscalationEsc4, $sSubject, $sOrigEscName, $sOrigTo, main::messagePostFixUp($sLastMessage)) . ($g_hEscalations{$sOrigEscName}->{rt_queue} ? $sRTSuffix : ''));

        }
    }
}



sub findUsersSchedules($) {
    my $iUser = shift;
    my @aScheds;

    # if we're given a name convert it to a phone number
    $iUser = DSPS_User::matchUserByRegex($iUser) if ($iUser !~ /^\d+$/);

    foreach my $sEscName (keys %g_hEscalations) {

        if (defined $g_hEscalations{$sEscName}->{schedule}) {
            my %hSchedule = %{ $g_hEscalations{$sEscName}->{schedule} };

            foreach my $sDate (keys %hSchedule) {

                if ($hSchedule{$sDate} =~ /$g_hUsers{$iUser}->{regex}/i) {
                    push(@aScheds, $sEscName);
                    last;
                }
            }
        }
    }

    return @aScheds;
}

# a user can be part of multiple escalations, each with it's own emails.
# collect them all
sub getUsersEscalationsEmails($) {
    my $iSender = shift;

    # look up all of the user's oncall schedules (escalations they're part of)
    my @aSenderEsc = findUsersSchedules($iSender);

    my @aEmails;
    foreach my $sEsc (@aSenderEsc) {
        push(@aEmails, $g_hEscalations{$sEsc}->{swap_email}) if $g_hEscalations{$sEsc}->{swap_email};
    }

    return join(', ', @aEmails);
}



sub swapSchedules($$;$) {
    my $iSender     = shift;
    my $sSwapeeName = shift;
    my $sTargetEsc  = shift || '';
    my $iSwapee     = DSPS_User::matchUserByRegex($sSwapeeName);

    # we need to determine if the two swapping users share a common oncall schedule
    my @aSenderEsc = findUsersSchedules($iSender);
    my @aSwapeeEsc = findUsersSchedules($sSwapeeName);

    # the sender isn't part of an oncall rotation
    return main::sendSmsPage($iSender, t(S_NothingToSwap)) if ($#aSenderEsc < 0);

    # the specified swapee isn't part of an oncall rotation
    return main::sendSmsPage($iSender, t(S_NoRecipSwap1, $sSwapeeName)) if ($#aSwapeeEsc < 0);

    # they're both part of at least one oncall rotation.  do they have any rotations in common?
    my @aMatches;
    foreach my $sSenderEntry (@aSenderEsc) {
        foreach my $sSwapeeEntry (@aSwapeeEsc) {
            push(@aMatches, $sSenderEntry) if ($sSenderEntry eq $sSwapeeEntry);
        }
    }

    # they have no rotations in common
    return main::sendSmsPage($iSender, t(S_NoSwapMatches1, $sSwapeeName)) if ($#aMatches < 0);

    # they have more than one in common so it's ambiguous
    return main::sendSmsPage($iSender, t(S_MultipleMatches3, $sSwapeeName, $sSwapeeName, join(', ', sort @aMatches))) if ($#aMatches > 0 && !$sTargetEsc);

    # they have more than one in common and have specified which to use with the common;  let's validate it
    if ($sTargetEsc) {
        my $bSuccess = 0;
        foreach my $sMatch (@aMatches) {
            if ($sMatch =~ /^$sTargetEsc$/i) {
                $sTargetEsc = $sMatch;
                $bSuccess   = 1;
                last;
            }
        }

        # the one they specified isn't on the "in common" list
        return main::sendSmsPage($iSender, t(S_UnsharedSchedule2, $sSwapeeName, $sTargetEsc)) unless $bSuccess;
    }
    else {
        # they have exactly one oncall rotation in common
        $sTargetEsc = $aMatches[0];
    }

    # by this point we know which escalation schedule ($sTargetEsc) we're doing the swap in.  it's a go!
    debugLog(D_escalations, "schedule swap of $sTargetEsc requested by " . $g_hUsers{$iSender}->{name} . " with $sSwapeeName");
    my %hSchedule = %{ $g_hEscalations{$sTargetEsc}->{schedule} };

    # build a searchable schedule hash
    my ($iMinute, $iHour, $iDay, $iMonth, $iYear) = (localtime)[1 .. 5];
    my $iToday = sprintf("%d%02d%02d", $iYear + 1900, $iMonth + 1, $iDay);
    my $iTodaySeconds = str2time($iToday);
    my %hFullSchedule;
    my @aAuto;

    foreach (sort keys %hSchedule) {

        if (($hSchedule{$_} =~ /^auto/i) || ($iTodaySeconds <= str2time($_) + 604000)) {
            my $iDateSeconds        = str2time($_);
            my $iNumberPeopleInAuto = 0;

            if ($hSchedule{$_} =~ /^auto/i) {
                my $bAutoArrayDone = 0;

                do {
                    my $sThisSched = $hSchedule{$_};

                    while ($sThisSched =~ m,(\w+),g) {
                        next if ($1 =~ /^auto$/i);
                        my $sSchedPerson = $1;

                        if (my $iFoundUser = DSPS_User::matchUserByRegex($sSchedPerson)) {
                            $hFullSchedule{$iDateSeconds} = $iFoundUser;
                            $iDateSeconds += ONEWEEK;    # advance a week
                            push(@aAuto, $iFoundUser) unless $bAutoArrayDone;
                        }
                    }

                    $bAutoArrayDone = 1;
                } while ($iTodaySeconds > $iDateSeconds - (ONEWEEK * scalar(@aAuto)));
            }
            else {
                my $sEntry = $hSchedule{$_};
                if (my $iFoundUser = DSPS_User::matchUserByRegex($sEntry)) {
                    $hFullSchedule{$iDateSeconds} = $iFoundUser;
                    $iDateSeconds += ONEWEEK;
                }
            }
        }
    }

    # prune old entries in the past

    foreach my $sDate (sort keys %hFullSchedule) {
        delete $hFullSchedule{$sDate} if ($sDate <= $iTodaySeconds - ONEWEEK);
    }

    # find the two entries to swap in the schedule

    my $iFirstDateSender = 0;
    my $iFirstDateSwapee = 0;
    foreach my $iDay (sort keys %hFullSchedule) {

        if (!$iFirstDateSender && ($iSender =~ /$hFullSchedule{$iDay}/i)) {
            $iFirstDateSender = $iDay;
        }

        if (!$iFirstDateSwapee && ($iSwapee =~ /$hFullSchedule{$iDay}/i)) {
            $iFirstDateSwapee = $iDay;
        }

        last if ($iFirstDateSender && $iFirstDateSwapee);
    }

    # this error should never happen given that we've checked for this at the beginning of this function
    return sendSmsPage($iSender, t("Unknown error - see system administrator")) if (!$iFirstDateSender || !$iFirstDateSwapee);

    # perform the swap
    $hFullSchedule{$iFirstDateSender} = $iSwapee;
    $hFullSchedule{$iFirstDateSwapee} = $iSender;

    # recreate the new schedule - find where to convert to "auto"

    my $bFail;
    my $iAutoDate = 0;
    foreach my $iDay (sort keys %hFullSchedule) {
        $bFail = 0;

        foreach my $iIndex (1 .. scalar(@aAuto)) {

            #print "   - looking at $iIndex on $iDay " . time2str("%x", $iDay + (($iIndex - 1) * ONEWEEK)) . "\n";
            last unless defined($hFullSchedule{ $iDay + (($iIndex - 1) * ONEWEEK) });

            #print "     - looking at " . $hFullSchedule{$iDay + (($iIndex - 1) * ONEWEEK)} . "\n";
            next if ($aAuto[$iIndex - 1] =~ /$hFullSchedule{$iDay + (($iIndex - 1) * ONEWEEK)}/i);

            #print "     - failed\n";
            $bFail = 1;
            last;
        }

        if (!$bFail) {
            $iAutoDate = $iDay;
            last;
        }
    }

    if (!$iAutoDate) {
        my @aTemp = sort keys %hFullSchedule;
        $iAutoDate = $aTemp[$#aTemp] + ONEWEEK;
        $hFullSchedule{$iAutoDate} = $aAuto[0];
    }

    # update the running schedule with our new one
    my $rFallbackSchedule = $g_hEscalations{$sTargetEsc}->{schedule};
    %hSchedule = ();
    foreach my $iDay (sort keys %hFullSchedule) {

        if ($iDay == $iAutoDate) {
            my $sAutoList = '';
            for my $sAutoEntry (@aAuto) {
                $sAutoList .= (length($sAutoList) ? ',' : '') . $g_hUsers{$sAutoEntry}->{name};
            }
            $hSchedule{ time2str("%Y%m%d", $iDay) } = "auto/$sAutoList";
            last;
        }
        else {
            $hSchedule{ time2str("%Y%m%d", $iDay) } = $g_hUsers{ $hFullSchedule{$iDay} }->{name};
        }
    }
    $g_hEscalations{$sTargetEsc}->{schedule} = \%hSchedule;

    if (my $sError = main::writeConfig()) {
        $g_hEscalations{$sTargetEsc}->{schedule} = $rFallbackSchedule;
        main::sendSmsPage($iSender, t("Swap failed due to system error; your admin has been notified by email."));
        main::sendEmail(main::getAdminEmail(), '',
                "Subject: DSPS Error in DSPS_Config::writeConfig()\n\n"
              . $g_hUsers{$iSender}->{name}
              . " attempted a schedule swap with "
              . $g_hUsers{$iSwapee}->{name} . ".\n"
              . "It failed while attempting to write the new config file to disk:\n$sError");
    }
    else {
        main::sendSmsPage($iSender, t(getFullOncallSchedule($sTargetEsc)));
        main::sendSmsPage($iSender, t(S_ScheduleSwap1, $g_hUsers{$iSwapee}->{name}));

        main::sendEmail($g_hEscalations{$sTargetEsc}->{swap_email},
            main::getAdminEmail(), sv(E_SwapSuccess4, $g_hUsers{$iSender}->{name}, $g_hUsers{$iSwapee}->{name}, $sTargetEsc, getFullOncallSchedule($sTargetEsc)));
    }
}

1;

