# vim:set ai noet sts=8 ts=8 sw=8 tw=0:
# Local Variables:
# mode:cperl
# cperl-indent-level:4
# End:

# Copyright © Stephen Gran 2009
# Copyright (c) 2010 Peter Palfrader <peter@palfrader.org>
#
# Author: Stephen Gran <steve@lobefin.net>, Peter Palfrader
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, under version 2 of the License.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 51 Franklin St, Fifth Floor, Boston, MA  02110-1301  USA

=head1 NAME

DNSHelpers - some building blocks used for debian.org's DNS scripts


=head1 FUNCTIONS

=over

=cut

package DNSHelpers;
@ISA = qw(Exporter);
require Exporter;
@EXPORT = qw(new_serial generate_zoneheader sign_zonefile);

use strict;
use warnings;
use POSIX qw(strftime);

=item B<new_serial> ($file, $outdir)

Storing state in $outdir/$file.serial, create a new serial number for use with
DNS.  This will generally be of the form YYMMDDnn, but be strictly larger than
any previously used number (so after ..99 we roll over to the "next day" if
necessary).

=cut

sub new_serial {
	my ($file, $outdir) = @_;

	$file .= '.serial';
	my $serial;
	my $newserial;
	my $today = strftime "%Y%m%d01", gmtime();
	
	if (-f "$outdir/$file") {
		open (SERIAL, "<", "$outdir/$file") or die "Cannot open $file for reading: $!";
		$serial = <SERIAL>;
		defined $serial or die "Cannot read serial $file: $!";
		close SERIAL;
		chomp $serial;
	}

	if ((defined $serial) && ($serial >= $today)) {
		$newserial = $serial + 1;
	} else {
		$newserial = $today;
	}

	open SERIAL, ">", "$outdir/$file" or die "Cannot open $file for writing: $!";
	print SERIAL "$newserial\n";
	close SERIAL or die "Closing $file failed: $!";
	return $newserial;
}

=item B<generate_zoneheader> ($serial, %vars)

Create a DNS zonefile header for bind, considing of an optional $TTL line
and the zone's SOA record.

The %vars hash needs to contain several keys:

=over 2

=item B<ttl>

used in the $TTL line (optional).

=item B<origin>

used in the SOA record.

=item B<hostmaster>

used in the SOA record.

=item B<refresh>

used in the SOA record.

=item B<retry>

used in the SOA record.

=item B<expire>

used in the SOA record.

=item B<negttl>

used in the SOA record.

=back

=cut

sub generate_zoneheader {
	my ($serial, %vars) = @_;

	my $header = '';
	$header .= "\$TTL	$vars{'ttl'}\n" if defined $vars{'ttl'};
	$header .= <<EOF;
@	IN	SOA	$vars{'origin'}. $vars{'hostmaster'}. (
	$serial	; serial number
	$vars{'refresh'}	; refresh
	$vars{'retry'}	; retry
	$vars{'expire'}	; expire
	$vars{'negttl'} )	; negative cache time-to-live
EOF
	return $header;
}

=item B<sign_zonefile> ($zonename, $zonefilename, $dnssigner, $confdnssec_key_ttl, $dnssec_signature_validity_period)

This signs the zone with origin at $zonename and stored in $zonefilename,
replacing the file with a DNSSEC signed version.

This function returns 0 if signing was not attempted (due to missing
parameters), undef if signing failed, and 1 if everything went fine.

It also dies if it cannot replace the file at $zonefilename with a new
file.

$dnssigner holds the path to the dnssigner script.

$dnssec_key_ttl is the TTL for the DNSKEY records (optional).

$dnssec_signature_validity_period is the validity period that signatures should
have (the name kinda gives it away; optional).

=cut
sub sign_zonefile {
	my ($zonename, $zonefile, $dnssigner, $confdnssec_key_ttl, $dnssec_signature_validity_period) = @_

	if (!defined $dnssigner}) {
		print STDERR "Warning: dnssec enabled for zone $zonename, but dnssigner not defined.  Disabling dnssec.\n";
		return 0;
	};

	# dnssigner -e +$(( 3600 * 24 * 2 )) -o palfrader.org palfrader.org
	my @cmd = ($dnssigner);
	push(@cmd, '-e', '+'.$dnssec_signature_validity_period) if defined $dnssec_signature_validity_period;
	push(@cmd, "-T", $dnssec_key_ttl) if ($dnssec_key_ttl);
	push(@cmd, '-o', $zonename);
	push(@cmd, $zonefilename);
	system(@cmd);
	if ($CHILD_ERROR >> 8 != 0) {
		return undef;
	}
	rename($zonefilename.'.signed', $zonefilename) or die "Cannot rename $zonefilename.signed to $zonefilename: $!\n";
	return 1;
}

}
1;
