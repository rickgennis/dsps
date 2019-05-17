package DSPS_String;

use DSPS_Debug;
use strict;
use warnings;

use base 'Exporter';
our @EXPORT = (
    't',                  'sv',               'cr',                'S_NoPermission',     'S_NoConversations',   'S_AudienceUpdate',    'S_YoureAlone',        'S_NotInRoom',
    'S_NowInMaint',       'S_UnknownCommand', 'S_NeedTime',        'S_RecoveryAlreadyF', 'S_RecoveryAlreadyU',  'S_RecoveryFiltered',  'S_RecoveryEnabled',   'S_NoReBroadcast',
    'S_NothingToSwap',    'S_NoRecipSwap1',   'S_SwapSyntax',      'S_NoSwapMatches1',   'S_MultipleMatches3',  'S_UnsharedSchedule2', 'S_ScheduleSwap1',     'C_PIDPath',
    'C_StatePath',        'S_AutoReplySyx',   'S_AutoReplySet1',   'S_AutoReplyRm',      'S_NoSuchEscalation1', 'S_NoEscalations',     'S_NoSuchEntity',      'S_NoSuchHelp',
    'S_PullSyntax',       'S_SmartAlreadyF',  'S_SmartFiltered',   'E_SwapSuccess4',     'S_EmailSent1',        'S_NeedEmail',         'E_VacationSet2',      'E_VacationCancel1',
    'E_VacationElapsed1', 'S_HelpGeneral',    'S_HelpCommandsA',   'S_HelpCommandsB',    'S_HelpSyntax',        'S_NoSuchTrigger',     'S_AutoNagiosMute',
    'S_SummaryTooLate', 'E_EscalationPrep3', 'E_EscalationEsc4',   'S_VacaNeedTime',      'S_NoVacations',       'S_AmbiguousIgnored1', 'S_AmbiguousReject2', 'S_NoSuchUser',
    'S_NoRecent', '@A_HelpTopics', 'E_StaycationSet2', 'E_StaycationCancel1', 'E_StaycationElapsed1', 'E_UserInvalidated1', 'S_AlreadySubscrbd1', 'S_SuccessSubscrbd1',
    'S_AlreadyUnSub1', 'S_SuccessUnSub1', 'S_SuccessUnAll', 'S_SendSyntax', 'S_NoSuchSubList1', 'S_SubMsgSent1', 'S_SubMsgTooLong', 'S_SubMsgTooLong1', 'S_NoMembership',
    'S_YoureOncall1', 'S_Welcome', 'E_OnCallDueToInvalidating4',
);

# String Templates
use constant S_NoPermission => "You don't have permission for this command.";
use constant S_NoReBroadcast =>
  "This room is already in broadcast mode from another sender & you don't have permission to override.  Your message was sent only to the original broadcaster.";
use constant S_NoConversations   => 'There are currently no rooms or conversations.';
use constant S_NoRecent          => 'There are no recent conversations logged.';
use constant S_AudienceUpdate    => 'Audience is now';
use constant S_YoureAlone        => "There's no one in this conversation other than you.  Mention a \@name or \@group to specify a recipient.";
use constant S_NotInRoom         => "You're not currently in a conversation/room.";
use constant S_NowInMaint        => 'designated this a maintenance window room.  Escalations will not fire for the duration of the room.';
use constant S_UnknownCommand    => 'Unrecognized command.';
use constant S_NeedTime          => "where T is time (e.g. 3h).  Units can be 'm'inutes, 'h'ours, 'd'ays, or 'w'eeks.";
use constant S_RecoveryAlreadyF  => "You already have recoveries filtered (blocked).  Use ':recovery' to re-enable them.";
use constant S_RecoveryAlreadyU  => "You already have recoveries enabled.  Use ':norecovery' to filter them.";
use constant S_RecoveryFiltered  => "Recovery pages are now filtered (blocked) for you.";
use constant S_SmartAlreadyF     => "You already have smart recoveries enabled.  Use ':recovery' to disable them.";
use constant S_SmartFiltered     => "Smart sleep recoveries are now enabled for you.";
use constant S_RecoveryEnabled   => "Recovery pages are now restored for you.";
use constant S_NothingToSwap     => "You aren't part of any oncall rotation schedule.  You have no schedule entry to swap.";
use constant S_NoRecipSwap1      => "%% isn't part of any oncall rotation schedule and therefore has nothing to swap.";
use constant S_SwapSyntax        => "You need to specify with whom to swap oncall schedules.  e.g. ':swap PERSON'.";
use constant S_NoSwapMatches1    => "You and %% don't share any oncall rotation schedules.  You can't swap into a different group.";
use constant S_MultipleMatches3  => "You and %% share multiple schedules.  Specify which, e.g. ':swap %% SCHEDULE' where SCHEDULE is one of %%.";
use constant S_UnsharedSchedule2 => "You and %% don't share a schedule on %%.";
use constant S_ScheduleSwap1     => "You've successfully swapped your next oncall week with %%.";
use constant S_AutoReplySet1     => "You have successfully set your auto reply for the next %%.";
use constant S_AutoReplySyx      => "You currently have no auto reply configured.  To set an auto reply use ':autoreply TIME MESSAGE'";
use constant S_AutoReplyRm       => "Your auto reply has been removed.";
use constant S_NoSuchEscalation1 => "There is no escalation named %%.";
use constant S_NoEscalations     => "There are no escalations currently configured";
use constant S_NoSuchEntity      => "There's no group, alias, escalation or user by that name.";
use constant S_EmailSent1        => "The room's history has been emailed to %%.";
use constant S_NeedEmail         => "You need to specify a recipient's email address.  e.g. ':email ADDRESS'";
use constant S_VacaNeedTime      => "The vacation/staycation commands needs a time specified.  e.g. ':vacation 3d' or ':vacation 5/2/14 17:00'";
use constant S_NoVacations       => "No one has currently configured stay/vacation time.";
use constant S_AmbiguousIgnored1 => "Ambiguous name reference '%%' ignored;  message was sent as is.";
use constant S_AmbiguousReject2  => "%% is ambiguous.  Try %%.";
use constant S_PullSyntax        => "Use ':pull NAMES' to pull users and/or groups into a new room with you, disbanding your previous room.";
use constant S_NoSuchHelp        => 'There are no help topics that match your search.';
use constant S_HelpGeneral       => "Use:\n  ?help TOPIC\nfor help on a particular subject, be it a command or general description (single word).\n\n  ?commands\nto get a list of commands.";
use constant S_HelpCommandsA     => "?oncall\n?rooms\n?vacation\n?filter\n?groups\n?NAME\n:macro\n:nonagios\nnorecovery\n:smartrecovery\n:vacation\n:leave\n:email";
use constant S_HelpCommandsB     => ":disband\n:pull NAMES\n:autoreply\n:sleep\n:maint\n:swap\n:ack\n?help TOPIC";
use constant S_HelpSyntax        => "?help TOPIC\nwhere topic can be a command, description or idea you help with.  Try to keep the topic to a single word for better results.";
use constant S_NoSuchTrigger     => "There are no triggers that match the name you provided.";
use constant S_AutoNagiosMute    => "Massive slew of Nagios pages.  Auto-filtering Nagios for the next 30 minutes.  Original cause persists.";
use constant S_SummaryTooLate    => "The previous conversation has already expired. It's too late to summarize.  You can try emailing it in.";
use constant S_NoSuchUser        => "There are no users or groups that match the name you specified.";
use constant S_AlreadySubscrbd1  => "You're already subscribed to the %% list.";
use constant S_SuccessSubscrbd1  => "You've successfully subscribed to the %% list.";
use constant S_AlreadyUnSub1     => "You aren't subscribed to the %% list.";
use constant S_SuccessUnSub1     => "You've been successfully removed from the %% list.";
use constant S_SuccessUnAll      => "You've been successfully removed from all subscription lists.";
use constant S_SendSyntax        => "The send command requires a subscription list name and the outgoing message text, e.g. :sendc2 Hi C2 list.";
use constant S_NoSuchSubList1    => "%% is not a currently configured subscription list.";
use constant S_SubMsgSent1       => "Your message was successfully sent to the %% list.";
use constant S_SubMsgTooLong     => 'Your message is 1 character too long. Please submit a shorter version.';
use constant S_SubMsgTooLong1    => 'Your message is %% characters too long.  Please submit a shorter version.';
use constant S_NoMembership      => "You aren't currently subscribed to any lists.";
use constant S_YoureOncall1      => "You are now on call for %%.";
use constant S_Welcome		 => "Welcome to DSPS!";

# Emails Templates
use constant E_SwapSuccess4 => "Subject: Oncall schedule change\n\n" . "%% has swapped weeks with %%.\n\n" . "The new schedule for %% is as follows:\n\n%%";
use constant E_VacationSet2 => "Subject: DSPS vacation time update\n\n"
  . "%% has set %% of vacation time and will be removed from all groups and escalations.  You can still contact this person directly by name.\n\n"
  . "The '?vacation' paging command can be used to see everyone that currently has vacation days configured.\n";
use constant E_VacationCancel1 => "Subject: DSPS vacation time update\n\n"
  . "%% has canceled their remaining vacation time and is now restored to all groups and escalations.\n\n"
  . "The '?vacation' paging command can be used to see everyone that currently has vacation days configured.\n";
use constant E_VacationElapsed1 => "Subject: DSPS vacation time update\n\n"
  . "%%'s vacation time has elapsed and is now restored to all groups and escalations.\n\n"
  . "The '?vacation' paging command can be used to see everyone that currently has vacation days configured.\n";

use constant E_StaycationSet2 => "Subject: DSPS staycation time update\n\n"
  . "%% has set %% of staycation time and will be removed from all groups and escalations during sleeping hours.  You can still contact this person directly by name.\n\n"
  . "The '?vacation' paging command can be used to see everyone that currently has stay/vacation days configured.\n";
use constant E_StaycationCancel1 => "Subject: DSPS staycation time update\n\n"
  . "%% has canceled their remaining staycation time and is now restored to all groups and escalations.\n\n"
  . "The '?vacation' paging command can be used to see everyone that currently has stay/vacation days configured.\n";
use constant E_StaycationElapsed1 => "Subject: DSPS staycation time update\n\n"
  . "%%'s staycation time has elapsed and is now restored to all groups and escalations.\n\n"
  . "The '?vacation' paging command can be used to see everyone that currently has stay/vacation days configured.\n";
use constant E_EscalationPrep3 => "Subject: %%\n\n" . "[%%]\n\n%%";
use constant E_EscalationEsc4  => "Subject: %%\n\n" . "[%%]\n\nThere was no reply from the on call person.  Escalating to:\n%%\n" . "\n%%";
use constant E_UserInvalidated1 => "Subject: DSPS paging user automatically dropped\n\n" . "User %% has an end of life ('valid') date specified in the DSPS config file.\n"
  . "That date has been reached and the user has been automatically dropped from the active running config.  No further action is required.\n";
use constant E_OnCallDueToInvalidating4 => "Subject: On call schedule changed for %%\n\n" . "%% has been removed from DSPS.  As a result the on call schedule for %% was recalculated.\n" 
  . "the new on call person is now %%.";

use constant C_PIDPath   => '/tmp/.dsps.pid';  
use constant C_StatePath => '/var/local/dsps';

our @A_HelpTopics = (
    ":vacation T (set)\n" . "?vacation (query)",

    ":macro NAME DEFINITION (set)\n" . ":macro NAME (delete)\n" . "?macros (query)\n" . ":nomacros (delete all)",

    ":disband (does current rm)\n" . ":pull NAMES (new rm w/names)",

    ":nonagios (block)\n"
      . ":nagios (unblock)\n"
      . ":noregex T RE (block)\n"
      . ":noregex 0 RE (unblock)\n"
      . ":sleep (load&recv 3h)\n"
      . ":nosleep\n"
      . ":maint (no escs)\n"
      . "?filters (query)",

    ":norecovery (block)\n" . ":smartrecovery (enable)\n" . ":recover (unblock)\n" . "?filters (query)",

    ":swap PERSON (swap on call)",

    ":autoreply T TEXT (set)\n" . ":noautoreply (delete)",

    ":email ADDRESS",

    "?triggers\n" . ":disarm NAME\n" . ":arm NAME",

    ":ack (enable room ack)",

    "?oncall\n" . "?rooms\n" . "?groups\n" . "?GROUP\n" . "?NAME",

    "?recents (show recent rooms)",
);

# substitute in variables
sub sv($;@) {
    my $sText = shift;

    while ($sText =~ /%%/) {
        my $sParam = shift || '';

        if ($sParam) {
            $sText =~ s/%%/$sParam/;
        }
        else {
            last;
        }
    }

    return $sText;
}

# theme system messages
sub t($;@) {
    my $sText = shift;

    return ('[' . sv($sText, @_) . ']');
}

# continue a line
sub cr($;$) {
    my $sText = shift;
    my $sDelimiter = shift || "\n";

    return ($sText ? "$sText$sDelimiter" : $sText);
}

1;
