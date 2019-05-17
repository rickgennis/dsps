package DSPS_Test;

use DSPS_Room;
use DSPS_User;
use DSPS_Escalation;
use DSPS_Debug;
use DSPS_Util;
use Data::Dumper;
use strict;
use warnings;

use base 'Exporter';
our @EXPORT = ();


sub performUtilTests() {
    my ($a, $b);

    ($a, $b) = parseUserTime('72h');
    ok($a == 259200 && $b eq '3 days', "parseUserTime('72h')");

    ($a, $b) = parseUserTime('9d');
    ok($a == 777600 && $b eq '1 week, 2 days', "parseUserTime('9d')");
}


sub performRoomAndUserTests() {
    my ($a, $b);
    my $iNow = time();
    my $sUserJim = '1234567890';
    my $sUserJoe = '1234567891';
    my $sUserNagios = '1234567892';
    my $sUser4 = '1234567893';
    my $sUser5 = '1234567894';

    $a = DSPS_Room::createRoom();
    ok($a && defined($g_hRooms{$a}) && $g_hRooms{$a}->{expiration_time} > time(), 'DSPS_Room::createRoom()');

    ok($#g_aRecentRooms == -1, 'blank recent rooms catalog to start');

    DSPS_Room::destroyRoom($a);
    ok(!defined($g_hRooms{$a}), 'DSPS_Room::destroyRoom()');

    ok(!$#g_aRecentRooms, 'DSPS_Room::catalogRecentRoom()');

    ok(!keys(%g_hUsers), 'blank initial user list');
    DSPS_User::createUser('TesterJim', 'testerjim', $sUserJim, 'ops', 100);
    ok($g_hUsers{1234567890}->{name} eq 'TesterJim', 'DSPS_User::createUser() name check');

    DSPS_User::createUser('TesterJoe', 'testerjoe', $sUserJoe, 'ops', 0);
    ok(keys(%g_hUsers) == 2, 'DSPS_User::createUser() count');

    DSPS_User::createUser('!Nagios', 'nagios', $sUserNagios, 'ops', 100);
    DSPS_User::createUser('user4', 'user4', $sUser4, 'ops', 100);
    DSPS_User::createUser('user5', 'user5', $sUser5, 'ops', 100);

    main::processMentions($sUserJim, 'hey @testerjoe', '');
    ok(keys(%g_hRooms) == 1 && keys(%{$g_hRooms{1}->{occupants_by_phone}}) == 2, "call user into room");

    my $iSavedNoNagios = DSPS_SystemFilter::getAllNagiosFilterTill();
    ok(main::handlePagingCommands($sUserJim, ':nonagios 2h') && DSPS_SystemFilter::getAllNagiosFilterTill() > $iNow + 3000, ':nonagios');
    ok(main::handlePagingCommands($sUserJim, ':nagios') && !DSPS_SystemFilter::getAllNagiosFilterTill(), ':nagios');
    DSPS_SystemFilter::setAllNagiosFilterTill($iSavedNoNagios);

    ok(main::handlePagingCommands($sUserJim, ':disband') && !keys(%g_hRooms) && !DSPS_Room::findUsersRoom($sUserJim), ':disband');

    my $iJimRoom;
    ok(main::handlePagingCommands($sUserJim, ':maint @testerjoe') && ($iJimRoom = DSPS_Room::findUsersRoom($sUserJim)) && $iJimRoom ==  DSPS_Room::findUsersRoom($sUserJoe) &&
        $g_hRooms{$iJimRoom}->{maintenance}, ':maint');

    ok(main::handlePagingCommands($sUserJim, ':ack') && $g_hRooms{DSPS_Room::findUsersRoom($sUserJim)}->{ack_mode}, ':ack set');
    $main::g_hConfigOptions{nagios_problem_regex} = 'PROBLEM';
    $main::g_hConfigOptions{nagios_recovery_regex} = 'RECOVERY';

    main::processPageEngine($sUserNagios, 'PROBLEM the sky is falling! @testerjoe'); 
    ok(main::processPageEngine($sUserNagios, 'PROBLEM the sky is falling! @testerjoe') eq 'Blocked by system filter (ackMode)', ":ack filter");

    main::processPageEngine($sUserJim, '@testerjoe, @user4');
    my $bSuccess = 1 if (DSPS_Room::roomStatus(2, 0, 0, 0, 0, 0) =~ /minus/);
    ok($bSuccess, "DSPS_Room::roomStatus() minus group member");
}


sub startTests(;$) {
    my $bDebug = shift || 0;
    require Test::More;
    import Test::More tests => 17;

    if ($bDebug) {
        $main::g_bTEST_RUN = 5;
        $main::g_iDebugTopics = $main::g_iTestingDebugTopics;
    }
    else {
        $main::g_bTEST_RUN = 10;
        $main::g_iDebugTopics = 0;
    }

    performUtilTests();
    performRoomAndUserTests();

    my $tBuilder = Test::More->builder;
    my $iFailures = grep !$_->{'ok'}, @{$tBuilder->{Test_Results}}[ 0 .. $tBuilder->{Curr_Test} - 1 ];
    note("\n\nDEBUG:  To rerun tests with debugging enabled use 'dsps -tsd'.") if ($iFailures && !$bDebug);

    return 0;
}

1;

