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

package DNSHelpers;
@ISA = qw(Exporter);
require Exporter;
@EXPORT = qw(new_serial generate_zoneheader);

use strict;
use warnings;
use POSIX qw(strftime);

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

1;
