package DSPS_CmdPermission;

use DSPS_User;
use DSPS_String;
use DSPS_Debug;
use strict;
use warnings;

use base 'Exporter';
our @EXPORT = ();

our %hCmdPermission;
our %hDefaultCmdPermission = (
    '??'          => 10,
    '?groups'     => 10,
    '?rooms'      => 20,
    '?oncall'     => 20,
    '?filters'    => 20,
    '?triggers'   => 20,
    '?recent'     => 35,
    '?vacation'   => 20,
    ':email'      => 10,
    ':macro'      => 10,
    ':autoreply'  => 15,
    ':vacation'   => 20,
    ':swap'       => 30,
    ':disband'    => 35,
    ':pull'       => 35,
    ':kick'       => 35,
    ':sum'        => 30,
    ':disarm'     => 40,
    ':arm'        => 40,
    ':sleep'      => 40,
    ':norecovery' => 20,
    ':maint'      => 50,
    ':ack'        => 50,
    ':nonagios'   => 50,
    ':noregex'    => 60,
    '^'           => 30,
    ':send'       => 90,
    ':welcome'	  => 90,
);



sub checkPermissions($$) {
    my ($iUser, $sCommand) = @_;
    my $iCommandPermission = defined $hCmdPermission{$sCommand} ? $hCmdPermission{$sCommand} : $hDefaultCmdPermission{$sCommand};
    my $bSuccess = $g_hUsers{$iUser}->{access_level} >= $iCommandPermission;

    debugLog(D_permissions,
            ($bSuccess ? 'PASS' : 'FAIL')
          . ", command: \"$sCommand\", requires: $iCommandPermission ["
          . (defined $hCmdPermission{$sCommand} ? 'specified' : 'default')
          . "], user ($iUser): "
          . $g_hUsers{$iUser}->{access_level});

    infoLog("Permission denied for " . $g_hUsers{$iUser}->{name} . " to run $sCommand") unless $bSuccess;
    return $bSuccess;
}



sub checkAndRefutePermissions($$) {
    my ($iUser, $sCommand) = @_;

    return 1 if checkPermissions($iUser, $sCommand);
    main::sendSmsPage($iUser, t(S_NoPermission));
    return 0;
}

1;

