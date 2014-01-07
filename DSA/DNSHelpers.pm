# vim:set ai noet sts=8 ts=8 sw=8 tw=0:
# Local Variables:
# mode:cperl
# cperl-indent-level:4
# End:

# Copyright © Stephen Gran 2009
# Copyright (c) 2010, 2013, 2014 Peter Palfrader <peter@palfrader.org>
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

DSA::DNSHelpers - some building blocks used for debian.org's DNS scripts


=head1 FUNCTIONS

=over

=cut

package DSA::DNSHelpers;
@ISA = qw(Exporter);
require Exporter;
@EXPORT = qw(get_serial new_serial generate_zoneheader check_zonefile compile_zonefile convert_time load_config);

use strict;
use warnings;
use POSIX qw(strftime);
use English;
use YAML;
use File::Temp qw(tempfile);

=item B<get_serial> ($zone, $outdir)

Storing state in $outdir/$zone.serial, get the current serial number for use with DNS.

=cut
sub get_serial {
	my ($zone, $outdir) = @_;

	my $filename = "$outdir/$zone.serial";

	return undef unless (-f $filename);

	open (SERIAL, "<", "$filename") or die "Cannot open $filename for reading: $!";
	my $serial = <SERIAL>;
	defined $serial or die "Cannot read serial $filename: $!";
	close SERIAL;
	chomp $serial;
	return $serial;
}

=item B<new_serial> ($zone, $outdir)

Storing state in $outdir/$zone.serial, create a new serial number for use with
DNS.  This will generally be of the form YYMMDDnn, but be strictly larger than
any previously used number (so after ..99 we roll over to the "next day" if
necessary).

=cut
sub new_serial {
	my ($zone, $outdir) = @_;

	my $newserial;
	my $today = strftime "%Y%m%d01", gmtime();

	my $serial = get_serial($zone, $outdir);

	if ((defined $serial) && ($serial >= $today)) {
		$newserial = $serial + 1;
	} else {
		$newserial = $today;
	}

	my ($fd, $serialfile) = tempfile("$zone.serial-XXXXXX", DIR => $outdir, SUFFIX => '.tmp');
	print $fd "$newserial\n";
	close $fd or die "Closing $serialfile failed: $!";
	(chmod(0644, $serialfile) == 1) or die ("Failed to chmod serialfile: $!\n");
	rename($serialfile, "$outdir/$zone.serial") or die ("Failed to rename serialfile to target name: $!\n");
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

=item B<check_zonefile> ($zonename, $zonefilename)

Run bind's named-checkzone to check a zonefile

returns undef on errors, 1 if OK.

=cut
sub check_zonefile {
	my ($zonename, $zonefilename, %options) = @_;

	my $integrity_check = 'full';
	$integrity_check = 'none' if $options{'no-integrity-checks'};

	system(qw{/usr/sbin/named-checkzone -q -k fail -n fail -S fail -m fail -M fail -i}, $integrity_check, $zonename, $zonefilename);
	if ($CHILD_ERROR >> 8 != 0) {
		system(qw{/usr/sbin/named-checkzone -k fail -n fail -S fail -i full -m fail -M fail}, $zonename, $zonefilename);
		return undef;
	};
	return 1;
}

=item B<compile_zonefile> ($zonename, $zonefilename)

Run bind's named-compilezone to compile a zonefile

returns undef on errors, 1 if OK.

=cut
sub compile_zonefile {
	my ($zonename, $in, $out) = @_;

	system(qw{/usr/sbin/named-compilezone -q -k fail -n fail -S fail -i none -m fail -M fail -o}, $out, $zonename, $in);
	if ($CHILD_ERROR >> 8 != 0) {
		return undef;
	};
	return 1;
}

=item B<convert_time> ($ticks, $unit)

Convert $ticks count of $unit (s, m, h, d, or w for seconds, minutes, hours,
days or weeks respectively) to seconds.  If $unit is undefined then $ticks
is parsed to see if it contains a unit character at the end.  If none if found
a warning is printed and the number assumed to be seconds.

=cut
sub convert_time {
	my $ticks = shift;
	my $unit = shift;

	unless (defined $unit) {
		my $newticks;
		($newticks, $unit) = $ticks =~ m/^(\d*)([smhdw]?)$/;
		if (!defined $newticks) {
			print STDERR "Warning: invalid timestring to convert '$ticks'\n";
			return $ticks;
		}
		$ticks = $newticks;
	}

	if ($unit eq 's' || $unit eq '') { }
	elsif ($unit eq 'm') { $ticks *= 60; }
	elsif ($unit eq 'h') { $ticks *= 60*60; }
	elsif ($unit eq 'd') { $ticks *= 60*60*24; }
	elsif ($unit eq 'w') { $ticks *= 60*60*24*7; }
	else { print STDERR "Warning: invalid unit '$unit'\n" }
	return $ticks;
}

=item B<load_config> (@keys)

Loads the configuration file.  @keys specifies a list of keys that must be
present or the function will die().

=cut

sub load_config {
	my @keys = @_;

	my $conffile = '/etc/dns-helpers.yaml';
	$conffile = $ENV{'DNSHELPERS_CONF'} if defined $ENV{'DNSHELPERS_CONF'};

	my $config = YAML::LoadFile $conffile;

	for my $key (@keys) {
		die ("$key not set in config\n") unless defined $config->{$key};
	};
	return $config;
};

1;
