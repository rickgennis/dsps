package DSPS_Room;

use DSPS_String;
use DSPS_User;
use DSPS_Debug;
use DSPS_Util;
use strict;
use warnings;

use base 'Exporter';
our @EXPORT = ('%g_hRooms', '@g_aRecentRooms');

our %g_hRooms;
our @g_aRecentRooms;

my $iLastRoomErrorTime = 0;


sub roomType($) {
    my $iRoom = shift;
    return '' unless ($iRoom && defined($g_hRooms{$iRoom}));

    my $sRoomType =
        ($g_hRooms{$iRoom}->{broadcast_speaker} ? 'B' : '')
        . ($g_hRooms{$iRoom}->{maintenance}       ? 'M' : '')
        . ($g_hRooms{$iRoom}->{ack_mode}          ? 'A' : '')
        . ($g_hRooms{$iRoom}->{ticket_number}     ? 'T' : '')
        . ($g_hRooms{$iRoom}->{escalation_time}   ? 'E' : '');

    return $sRoomType ? "[$sRoomType]" : '';
}


sub sendRecentRooms($) {
    my $iSender = shift;
    my $sResult = '';

    if ($#g_aRecentRooms >= 0) {
        foreach my $tR (reverse @g_aRecentRooms) {
            my $sEntry = prettyDateTime($tR->{creation_time}, 1) . ": " . roomStatusIndividual(0, 0, 0, 0, $tR->{most_occupants_by_phone}) . "\n";
            $sResult .= $iSender ? main::sendSmsPage($iSender, $sEntry . $tR->{summary}) : ("$sEntry\t" . $tR->{summary} . "\n");
        }
    }
    else {
        $sResult = $iSender ? main::sendSmsPage($iSender, t(S_NoRecent)) : S_NoRecent . "\n";
    }

    return $sResult;
}


sub catalogRecentRoom($) {
    my $iRoom = shift;
    return unless $iRoom;

    my @aRecentCopy = @g_aRecentRooms;
    foreach my $tR (@aRecentCopy) {
        if ($tR->{creation_time} < $main::g_iLastWakeTime - 86400) {
            shift @g_aRecentRooms;
            debugLog(D_rooms, "pruned a room");
        }
        else {
            last;
        }
    }

    my $tRoom = {
        creation_time => $g_hRooms{$iRoom}->{creation_time},
        summary => $g_hRooms{$iRoom}->{summary},
        most_occupants_by_phone => $g_hRooms{$iRoom}->{most_occupants_by_phone},
    };

    debugLog(D_rooms, "cataloged a recent room, ct=" . $g_hRooms{$iRoom}->{creation_time});
    push(@g_aRecentRooms, $tRoom);
}


# customized sort to put humans before system users
sub humanSort {
    my $bA = ($a =~ /^\!/);
    my $bB = ($b =~ /^\!/);

    return 1  if ($bA && !$bB);
    return -1 if ($bB && !$bA);
    return ($a cmp $b);
}



sub createRoom {
    my $iEmptyRoom = 0;
    while (defined $g_hRooms{ ++$iEmptyRoom }) {1;}

    $g_hRooms{$iEmptyRoom} = {
        occupants_by_phone       => {},
        saved_occupants_by_phone => {},
        most_occupants_by_phone  => {},
        expiration_time          => $main::g_iLastWakeTime + ROOM_LENGTH,
        escalation_time          => 0,
        escalation_to            => '',
        escalation_orig_sender   => '',
        escalation_name          => '',
        ticket_number            => 0,
        broadcast_speaker        => 0,
        history                  => [],
        maintenance              => 0,
        last_maint_warning       => 0,
        ack_mode                 => 0,
        last_problem_time        => 0,
        last_human_reply_time    => 0,
        creation_time            => $main::g_iLastWakeTime,
        last_nonhuman_message    => '',
        summary                  => '',
        sum_reminder_sent        => '',
    };

    debugLog(D_rooms, "created room #$iEmptyRoom with expiration of " . $g_hRooms{$iEmptyRoom}->{expiration_time});
    return $iEmptyRoom;
}



sub destroyRoom($) {
    my $iRoomNumber = shift;
    catalogRecentRoom($iRoomNumber);
    delete $g_hRooms{$iRoomNumber};
    debugLog(D_rooms, "cleaned up room #$iRoomNumber");
}



sub cloneRoomMinusOccupants($;$) {
    my $iOrigRoom = shift;
    my $bKeepSystemUsers = shift || 0;
    my $iNewRoom  = createRoom();

    $g_hRooms{$iNewRoom}->{most_occupants_by_phone} = $g_hRooms{$iOrigRoom}->{most_occupants_by_phone};
    $g_hRooms{$iNewRoom}->{escalation_orig_sender}  = $g_hRooms{$iOrigRoom}->{escalation_orig_sender};
    $g_hRooms{$iNewRoom}->{ticket_number}           = $g_hRooms{$iOrigRoom}->{ticket_number};
    $g_hRooms{$iNewRoom}->{history}                 = $g_hRooms{$iOrigRoom}->{history};
    $g_hRooms{$iNewRoom}->{maintenance}             = $g_hRooms{$iOrigRoom}->{maintenance};
    $g_hRooms{$iNewRoom}->{ack_mode}                = $g_hRooms{$iOrigRoom}->{ack_mode};
    $g_hRooms{$iNewRoom}->{last_problem_time}       = $g_hRooms{$iOrigRoom}->{last_problem_time};
    $g_hRooms{$iNewRoom}->{last_human_reply_time}   = $g_hRooms{$iOrigRoom}->{last_human_reply_time};
    $g_hRooms{$iNewRoom}->{creation_time}           = $main::g_iLastWakeTime;
    $g_hRooms{$iNewRoom}->{last_nonhuman_message}   = $g_hRooms{$iOrigRoom}->{last_nonhuman_message};
    $g_hRooms{$iNewRoom}->{summary}                 = $g_hRooms{$iOrigRoom}->{summary};
    $g_hRooms{$iNewRoom}->{sum_reminder_sent}       = $g_hRooms{$iOrigRoom}->{sum_reminder_sent};

    if ($bKeepSystemUsers) {
        for my $iUser (%{$g_hRooms{$iOrigRoom}->{occupants_by_phone}}) {
            roomEnsureOccupant($iNewRoom, $iUser) if !DSPS_User::humanUsersPhone($iUser);
        }
    }

    debugLog(D_rooms, "room $iOrigRoom cloned to $iNewRoom");
    return $iNewRoom;
}



sub checkpointOccupants($) {
    my $iRoom = shift;

    if ($iRoom && (defined $g_hRooms{$iRoom})) {
        my %SavedOccupants = defined($g_hRooms{$iRoom}->{occupants_by_phone}) ? %{ $g_hRooms{$iRoom}->{occupants_by_phone} } : {};
        $g_hRooms{$iRoom}->{saved_occupants_by_phone} = \%SavedOccupants;
    }
}



sub diffOccupants($) {
    my $iRoom = shift;
    my %hPrevOccupants = defined($g_hRooms{$iRoom}->{saved_occupants_by_phone}) ? %{ $g_hRooms{$iRoom}->{saved_occupants_by_phone} } : {};
    my @aResult;

    foreach my $iPhone (keys %{ $g_hRooms{$iRoom}->{occupants_by_phone} }) {
        push(@aResult, $iPhone) unless defined($hPrevOccupants{$iPhone});
    }

    debugLog(D_pageEngine, "diff is [" . join(', ', @aResult) . ']') if ($#aResult > -1);

    return @aResult;
}



sub combinePeoplesRooms($$) {
    my ($rTargetUser, $rDraggedUser) = @_;
    my $bRoomChanged = 0;

    my $iDestinationRoom = findUsersRoom($rTargetUser->{phone});
    my $iSourceRoom      = findUsersRoom($rDraggedUser->{phone});

    # is the sender already in a room or do we need to create one?
    $iDestinationRoom = createRoomWithUser($rTargetUser->{phone}) unless ($iDestinationRoom);

    # are the sender and the mentioned user the same person or already in the same room?
    unless (($iSourceRoom == $iDestinationRoom) || ($rTargetUser->{phone} == $rDraggedUser->{phone})) {
        $bRoomChanged = 1;

        if ($iSourceRoom) {

            # dragged user was in a different room
            # now we move over everyone that was in that (source) room
            foreach my $iUserInSourceRoom (keys %{ $g_hRooms{$iSourceRoom}->{occupants_by_phone} }) {
                roomRemoveOccupant($iSourceRoom, $iUserInSourceRoom);
                roomEnsureOccupant($iDestinationRoom, $iUserInSourceRoom);
            }

            $g_hRooms{$iDestinationRoom}->{maintenance}            = $g_hRooms{$iSourceRoom}->{maintenance}            unless $g_hRooms{$iDestinationRoom}->{maintenance};
            $g_hRooms{$iDestinationRoom}->{ack_mode}               = $g_hRooms{$iSourceRoom}->{ack_mode}               unless $g_hRooms{$iDestinationRoom}->{ack_mode};
            $g_hRooms{$iDestinationRoom}->{broadcast_speaker}      = $g_hRooms{$iSourceRoom}->{broadcast_speaker}      unless $g_hRooms{$iDestinationRoom}->{broadcast_speaker};
            $g_hRooms{$iDestinationRoom}->{ticket_number}          = $g_hRooms{$iSourceRoom}->{ticket_number}          unless $g_hRooms{$iDestinationRoom}->{ticket_number};
            $g_hRooms{$iDestinationRoom}->{escalation_orig_sender} = $g_hRooms{$iSourceRoom}->{escalation_orig_sender} unless $g_hRooms{$iDestinationRoom}->{escalation_orig_sender};

            destroyRoom($iSourceRoom);
        }
        else {
            # add the dragged user to the room
            roomEnsureOccupant($iDestinationRoom, $rDraggedUser->{phone});
            debugLog(D_rooms, 'user ' . $rDraggedUser->{name} . " (" . $rDraggedUser->{phone} . ") added to room $iDestinationRoom");
        }

        return 1;
    }

    return $bRoomChanged;
}



sub findUsersRoom($) {
    my $iUser = shift;

    foreach my $iRoom (keys %g_hRooms) {
        return $iRoom if (defined ${ $g_hRooms{$iRoom}->{occupants_by_phone} }{$iUser});
    }

    return 0;
}



sub createRoomWithUser($) {
    my $iUser = shift;

    my $iRoom = createRoom();
    roomEnsureOccupant($iRoom, $iUser);
    debugLog(D_rooms, 'user ' . $g_hUsers{$iUser}->{name} . " ($iUser) added to room $iRoom on create");

    return $iRoom;
}



sub findOrCreateUsersRoom($) {
    my $iUser = shift;
    my $iRoom = findUsersRoom($iUser);

    $iRoom = createRoomWithUser($iUser) unless $iRoom;

    return $iRoom;
}



sub roomHumanCount($) {
    my $iRoom      = shift;
    my $iOccupants = 0;

    if (defined $g_hRooms{$iRoom}) {
        foreach my $iPhone (keys %{ $g_hRooms{$iRoom}->{occupants_by_phone} }) {
            $iOccupants++ if (DSPS_User::humanUsersPhone($iPhone));
        }
    }

    return $iOccupants;
}



sub roomStatus($;$$$$$) {
    my $iTargetRoom        = shift;
    my $bNoGroupNames      = shift || 0;
    my $bSquashSystemUsers = shift || 0;
    my $bUseMostOccupants  = shift || 0;
    my $rOccupantsByPhone  = shift || 0;
    my $bIncludeType       = shift || 0;
    my $sFullResult        = '';

    foreach my $iRoom (sort keys %g_hRooms) {
        next if ($iTargetRoom && ($iRoom != $iTargetRoom));    # target == 0 means all rooms
        next unless ($rOccupantsByPhone || validRoom($iRoom));

        my $sType = $bIncludeType ? roomType($iRoom) : '';
        $sType = $sType ? " $sType" : '';

        $sFullResult = cr($sFullResult) . ($iTargetRoom ? '' : "R$iRoom") . $sType . ($iTargetRoom ? '' : ': ') . roomStatusIndividual($iRoom, $bNoGroupNames, $bSquashSystemUsers, $bUseMostOccupants, $rOccupantsByPhone);
    }

    return $sFullResult ? $sFullResult : S_NoConversations;
}


sub roomStatusIndividual($;$$$$) {
    my $iTargetRoom        = shift;
    my $bNoGroupNames      = shift || 0;
    my $bSquashSystemUsers = shift || 0;
    my $bUseMostOccupants  = shift || 0;
    my $rOccupantsByPhone  = shift || 0;
    my %hOccupantsByPhone  = $rOccupantsByPhone ? %{$rOccupantsByPhone} : ();
    my $sFullResult        = '';
    my %hFullHash          = ();

    if ($rOccupantsByPhone || validRoom($iTargetRoom)) {
        my $iRoom = $iTargetRoom;

        # depending on how we're called we may need to calculate room status for one of three different hashes:
        #  * a room's current occupants (part of the room struct)
        #  * a room's most occupants (part of a the room struct)
        #  * $rOccupantsbyPhone - a reference to an arbitrary hash that's passed in
        my %hRoomOccupants = $rOccupantsByPhone ? %hOccupantsByPhone : %{ ($bUseMostOccupants ? $g_hRooms{$iRoom}->{most_occupants_by_phone} : $g_hRooms{$iRoom}->{occupants_by_phone}) };

        # the list of people can get pretty long if we try to print them all one by one (let's call that option A).
        # if requested (via parameters) we can look to see how many members of a group are present in the room.
        # if every member of a group is present, we can remove the individual names and replace them by the group name.
        # let's call that option B.
        unless ($bNoGroupNames) {

            # loop through each defined group in the config file
            foreach my $sGroup (DSPS_User::allGroups()) {
                my %hOrigRoomOccupants = %hRoomOccupants;
                my %hGroupMembers;

                # %hGroupMembers is a temporary hash for this loop
                # let's start by entering all group members from the current group into this hash
                $hGroupMembers{$_}++ for (DSPS_User::usersInGroup($sGroup));
                my $iTotalInGroup = keys(%hGroupMembers);
                next if $iTotalInGroup < 2;

                # now we loop through people that are part of the current group.  for each group member
                # that's present in the room we
                #   * remove them from the room (%hRoomOccupants)
                #   * remove them from the temporary %hGroupMembers hash
                foreach my $sPersonInGroup (keys %hGroupMembers) {
                    if (defined $hRoomOccupants{$sPersonInGroup}) {
                        delete $hRoomOccupants{$sPersonInGroup};
                        delete $hGroupMembers{$sPersonInGroup};
                    }
                }

                # at this point:
                # hRoomOccupants = people in the room minus members of the current group (also minus previously handled groups from previous loops)
                # hGroupMembers = members of the current group that are NOT in the room
                my $iGroupMemsNOTinRoom = keys(%hGroupMembers);

                # if there are any group members left in the room then we know the entire group isn't in the room.
                # so we can't remove all their names and replace them with the group name.  notice we've been removing
                # them from the room one by one in the above loop.  so if the below if() is true (again, meaning not
                # the entire group is present) then we need to add them back.
                if ($iGroupMemsNOTinRoom) {
                    my $iGroupMemsInRoom = $iTotalInGroup - $iGroupMemsNOTinRoom;

                    # here we know we need to add them back to the room.  but let's consider another possibility for how to simplify
                    # lengthy output.  we know we can't just use the group name because not everyone is in the room (option B).  so either we
                    # can list each person individually (option A) -- that's good if only a few people from the group are present.  or we
                    # can say "groupFoo minus personA, personB" kind of thing (option C).  is our output more concise with A or C?  obviously
                    # this depends on how many people are in the group and what percentage of them are in the room versus not.  let's pretend
                    # all names (including the group name itself) are the same length, and we'll say the word "minus" counts as a name too.
                    # then the question of option A vs C comes down to:
                    if ($iGroupMemsInRoom > $iGroupMemsNOTinRoom + 2) {                 # only valid for groups of 5 or more

                        # here we've decided to do option C:  groupFoo (minus personA)
                        # we use the parens to distinguish between:
                        # groupA minus personJ, personF, personG, groupB
                        # without parents you might not know if personF is part of groupA and being subtracted from it or is a standalone
                        # individual that's in addition to "groupA minus personJ."  so:
                        # groupA (minus personJ, personF), personG, groupB
                        # is much clearer.

                        # at this point %hGroupMembers is a hash of everyone that's in the currently being processed group but is NOT
                        # present in the room.  we're going to prep these people for the "minus" part of our status

                        # convert phone numbers to names
                        foreach my $iPhone (keys %hGroupMembers) {
                            if (defined $g_hUsers{$iPhone}) {
                                delete $hGroupMembers{$iPhone};
                                $hGroupMembers{ $g_hUsers{$iPhone}->{name} } = 1 if (DSPS_User::humanUsersPhone($iPhone) || ($bSquashSystemUsers == -1) || (!$bSquashSystemUsers && main::getShowNonHuman()));
                            }
                        }

                        # all the group's individuals have been removed from the room (far above).  now we just need to
                        # add back a single entry of "groupNAME (minus missingPeople)" - we make it a single entry
                        # so that the final sort at the bottom keeps these pieces together as a single string
                        $hRoomOccupants{$sGroup . " (minus " . join(', ', sort humanSort keys(%hGroupMembers)) . ")"} = 1;
                    }
                    else {
                        # here we're at the straight, unsimplified version of option A - just list all the names.
                        # at this point all of our simplifications have failed and we're reverting to the original
                        # list of occupants that were passed into us.  the currently being processed group name can't
                        # be used to simplify.
                        %hRoomOccupants = %hOrigRoomOccupants;
                    }
                }
                else {
                    # option B - all members of the currently being processed group are present in the room and their
                    # names have been removed one by one as we were checking them.  now we just have to add back the
                    # group name in their place.
                    $hRoomOccupants{$sGroup} = 1 if (DSPS_User::humanTest($sGroup)
                        || ($bSquashSystemUsers == -1) || (!$bSquashSystemUsers && main::getShowNonHuman()));    # human-based group actually
                }
            }
        }

        # convert remaining phone numbers to names
        foreach my $iPhone (keys %hRoomOccupants) {
            if (defined $g_hUsers{$iPhone}) {
                delete $hRoomOccupants{$iPhone};
                $hRoomOccupants{ $g_hUsers{$iPhone}->{name} } = 1 if (DSPS_User::humanUsersPhone($iPhone)
                    || ($bSquashSystemUsers == -1) || (!$bSquashSystemUsers && main::getShowNonHuman()));
            }
        }

        # construct a string of all the completed hash entries
        $sFullResult = cr($sFullResult) . join(', ', sort humanSort keys(%hRoomOccupants));

        # construct a hash in case that's requested
        @hFullHash{ keys %hRoomOccupants } = values %hRoomOccupants;
    }

    return (wantarray() ? sort(keys(%hFullHash)) : ($sFullResult ? $sFullResult : S_NoConversations));
}



sub roomEnsureOccupant {
    my ($iRoomNumber, $sUserPhone) = @_;

    $g_hRooms{$iRoomNumber}->{occupants_by_phone}{$sUserPhone}      = 1;
    $g_hRooms{$iRoomNumber}->{most_occupants_by_phone}{$sUserPhone} = 1;
    debugLog(D_rooms, "adding user with phone $sUserPhone to room #$iRoomNumber");
}



sub roomRemoveOccupant {
    my ($iRoomNumber, $sUserPhone) = @_;

    delete $g_hRooms{$iRoomNumber}->{occupants_by_phone}{$sUserPhone};
    debugLog(D_rooms, "removing user with phone $sUserPhone from room #$iRoomNumber");
}



sub validRoom($) {
    my $iRoom = shift;

    unless ($g_hRooms{$iRoom}->{expiration_time} && $g_hRooms{$iRoom}->{occupants_by_phone}) {
	my $sOcc = (defined $g_hRooms{$iRoom}->{occupants_by_phone}) ? 
		keys(%{ $g_hRooms{$iRoom}->{occupants_by_phone} }) . ': ' . join(', ', keys(%{ $g_hRooms{$iRoom}->{occupants_by_phone} }))
		: 'undefined';

        infoLog("ERROR: room $iRoom looks invalid (expiration time = " . $g_hRooms{$iRoom}->{expiration_time} . "; occupants = $sOcc)"); 

        unless ($iLastRoomErrorTime && ($iLastRoomErrorTime > $main::g_iLastWakeTime - 3600)) {
            $iLastRoomErrorTime = $main::g_iLastWakeTime;
            main::sendEmail(main::getAdminEmail(), '',
                    "Subject: DSPS bug detected - invalid room found in roomStatus()\n\nRoom $iRoom doesn't look legit. Check:\n"
                  . "\"grep dsps /var/log/syslog\" around\n"
                  . localtime($main::g_iLastWakeTime));
        }

        return 0;
    }

    return 1;
}



sub roomsHealthCheck {
    foreach my $iRoomNumber (keys %g_hRooms) {
        next unless validRoom($iRoomNumber);

        # room half-way to expired
        if (($g_hRooms{$iRoomNumber}->{expiration_time} <= $main::g_iLastWakeTime + (ROOM_LENGTH / 2))
            && $g_hRooms{$iRoomNumber}->{last_nonhuman_message})
        {    # it wasn't just a human-to-human chat

            # admin has summary reminders enabled, it's day-time,
            # summary hasn't been set and reminder hasn't been sent
            if (main::getSummaryReminder() && main::getSummaryText()
                && isDuringWakingHours()
                && !$g_hRooms{$iRoomNumber}->{summary}
                && !$g_hRooms{$iRoomNumber}->{sum_reminder_sent}) {

                my @aReminderText = split('\s*\|\s*', main::getSummaryText());
                main::sendCustomSystemMessageToRoom((keys(%{ $g_hRooms{$iRoomNumber}->{occupants_by_phone} }))[0], $aReminderText[int(rand($#aReminderText+1))], 0, 1);
                $g_hRooms{$iRoomNumber}->{sum_reminder_sent} = 1;
            }

        }

        # room expired
        if ($g_hRooms{$iRoomNumber}->{expiration_time} <= $main::g_iLastWakeTime) {
            infoLog("room $iRoomNumber expired with " . keys(%{ $g_hRooms{$iRoomNumber}->{occupants_by_phone} }) . " occupants (" . roomStatusIndividual($iRoomNumber, 0, -1, 0, 0) . ')');
            logRoom($iRoomNumber);
            catalogRecentRoom($iRoomNumber);
            delete $g_hRooms{$iRoomNumber};
        }
    }
}


sub maintRoomWarningCheck() {
    foreach my $iRoom (keys %g_hRooms) {
        next unless ($g_hRooms{$iRoom}->{maintenance});

        if (($g_hRooms{$iRoom}->{expiration_time} - $main::g_iLastWakeTime < 600) &&       # room expires within 10 mins
            ($main::g_iLastWakeTime - $g_hRooms{$iRoom}->{last_maint_warning} > 2700)) {   # warning not sent for last 45 mins
            $g_hRooms{$iRoom}->{last_maint_warning} = $main::g_iLastWakeTime;
            main::sendCustomSystemMessageToRoom((keys(%{ $g_hRooms{$iRoom}->{occupants_by_phone} }))[0], "Your :maint room is about to expire.  Reply within the next 10 minutes to extend it.", 1, 1);    
        }
    }
}


sub logRoom($) {
    my $iRoom    = shift;
    my $sLogFile = main::getLogRoomsTo();
    use constant ONLY_LOG_SUMMARIZED => 1;

    if ((defined $g_hRooms{$iRoom}) && $sLogFile && !$main::g_bTEST_RUN) {
        open(LOG, ">>$sLogFile") || return infoLog("Unable to write to $sLogFile");

        if (($g_hRooms{$iRoom}->{summary} && ($g_hRooms{$iRoom}->{summary} =~ /^(.*?)\s*;\s*(.*)$/)) || !ONLY_LOG_SUMMARIZED) {
            print LOG localtime($g_hRooms{$iRoom}->{creation_time}) . " for " . prettyDuration($main::g_iLastWakeTime - $g_hRooms{$iRoom}->{creation_time}, 1) . "\nAudience: ";
            print LOG roomStatus($iRoom, 0, 1, 1) . "\n";

            if ($g_hRooms{$iRoom}->{summary} && ($g_hRooms{$iRoom}->{summary} =~ /^(.*?)\s*;\s*(.*)$/)) {
                my $sDesc   = ucfirst($1);
                my $sImpct  = ucfirst($2);
                my $sDetail = ${ $g_hRooms{$iRoom}->{history} }[0];
                $sDetail =~ s/\n/ /g;
                print LOG "\n\t* $sDetail\n\n";
                print LOG "Description: $sDesc\n";
                print LOG "Station Impact: $sImpct\n";
            }
            else {
                foreach my $sHistory (@{ $g_hRooms{$iRoom}->{history} }) {
                    $sHistory =~ s/\n/; /g;
                    print LOG $sHistory . "\n";
                }
            }

            print LOG "\n--------------------------------------------------------------------------------\n";
        }

        close(LOG);
    }
}

1;

