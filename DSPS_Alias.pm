package DSPS_Alias;

use DSPS_Debug;
use strict;
use warnings;

use base 'Exporter';
our @EXPORT = ('%g_hAliases');

our %g_hAliases;



sub createAlias {
    my $rhAlias = {
        name     => $_[0],
        referent => $_[1],
        hidden   => $_[2],
    };

    $g_hAliases{ $_[0] } = $rhAlias;
    debugLog(D_users, "creating alias $_[0]");

    return $rhAlias;
}



sub visibleAliases() {
    my @aVisibles;

    foreach my $sAlias (keys %g_hAliases) {
        push(@aVisibles, $sAlias) unless ($g_hAliases{$sAlias}->{hidden});
    }

    return @aVisibles;
}

1;
