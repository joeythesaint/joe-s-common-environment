#!/usr/bin/perl -w
#
#     Copyright (C) 2000-2003 Marc de Courville <marc@courville.org>
#     Copyright (C) 2005      Roland Rosenfeld <roland@spinnaker.de>
#
#     $Id: mutt_ldap_query.pl.in,v 1.20 2005-10-29 14:48:11 roland Exp $
#
#     This program is free software; you can redistribute it and/or modify
#     it under the terms of the GNU General Public License as published by
#     the Free Software Foundation; either version 2 of the License, or
#     (at your option) any later version.
#
#     This program is distributed in the hope that it will be useful,
#     but WITHOUT ANY WARRANTY; without even the implied warranty of
#     MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#     GNU General Public License for more details.
#
#     You should have received a copy of the GNU General Public License
#     along with this program; if not, write to the Free Software Foundation,
#     Inc., 51 Franklin St, Fifth Floor, Boston, MA 02110-1301,, USA.

use strict;
use Getopt::Long;
use Net::LDAP;
use Pod::Usage;

#------8<------8<------8<------8<---cut here--->8------>8------>8------>8------
# The defaults
my $man = 0;
my $help = 0;
my $DEBUG = 0;
my $lbdb_output = 0;
my $version = 0;
my $ldap_server_nickname = '';
my $config_file = '';

# hostname of your ldap server
our $ldap_server = 'ldap.four11.com';
# ldap base search
our $search_base = 'c=US';
# list of the fields that will be used for the query
our $ldap_search_fields = 'givenname sn cn';
# list of the fields that will be used for composing the answer
our $ldap_expected_answers = 'givenname sn mail o';
# format of the email result based on the expected answers of the ldap query
our $ldap_result_email = '${mail}';
# format of the realname result based on the expected answers of the ldap query
our $ldap_result_realname = '${givenname} ${sn}';
# format of the comment result based on the expected answers of the ldap query
our $ldap_result_comment = '(${o})';
# use ignorant (wildcard searching):
our $ignorant = 0;
# LDAP bind DN:
our $ldap_bind_dn = '';
# LDAP bind password:
our $ldap_bind_password = '';
# disable LDAP ssl query by default
our $ldap_ssl = 0;

our %ldap_server_db = (
  'four11'		=> ['ldap.four11.com', 'c=US', 'givenname sn cn mail', 'givenname cn sn mail o', '${mail}', '${givenname} ${sn}', '${o}' ],
  'infospace'		=> ['ldap.infospace.com', 'c=US', 'givenname sn cn mail', 'givenname cn sn mail o', '${mail}', '${givenname} ${sn}', '${o}' ],
  'whowhere'		=> ['ldap.whowhere.com', 'c=US', 'givenname sn cn mail', 'givenname cn sn mail o', '${mail}', '${givenname} ${sn}', '${o}' ],
  'bigfoot'		=> ['ldap.bigfoot.com', 'c=US', 'givenname sn cn mail', 'givenname cn sn mail o', '${mail}', '${givenname} ${sn}', '${o}' ],
  'switchboard'		=> ['ldap.switchboard.com', 'c=US', 'givenname sn cn mail', 'givenname cn sn mail o', '${mail}', '${givenname} ${sn}', '${o}' ],
  'infospacebiz'	=> ['ldapbiz.infospace.com', 'c=US', 'givenname sn cn mail', 'givenname cn sn mail o', '${mail}', '${givenname} ${sn}', '${o}' ]
);
#------8<------8<------8<------8<---cut here--->8------>8------>8------>8------

# Return version string from CVS tag
sub versionstring {
  my $ver = ' $Name: debian_version_0_31_1 $ ';
  $ver =~ s/Name//g;
  $ver =~ s/[:\$]//g;
  $ver =~ s/\s+//g;
  $ver =~ s/^v//g;
  $ver =~ s/_/\./g;
  if ($ver eq '') {
    $ver = "devel";
  }
  return($ver . " <marc\@courville.org>");
}

# Source a perl file
sub process_file {
  foreach my $file (@_) {
    if (-r $file) {
      unless (my $return = do $file) {
	warn "couldn't parse $file: $@" if $@;
	warn "couldn't do $file: $!" unless defined $return;
	warn "couldn't run $file" unless $return;
      }
    }
#    else {
#      warn "either $file doesn't exist or is not readable by me!\n";
#    }
  }
}

# first we need to apply defaults
process_file("/etc/lbdb_ldap.rc",
             "/etc/mutt_ldap_query.rc",
             "$ENV{HOME}/.lbdb/ldap.rc",
	     "$ENV{HOME}/.mutt_ldap_query.rc");


# Parse command line options. They override system defaults.
GetOptions (
  'config_file|c=s'		=> \$config_file,
  'server|ls=s'			=> \$ldap_server,
  'search_base|sb:s'		=> \$search_base,
  'search_fields|sf:s'		=> \$ldap_search_fields,
  'expected_answers|ea:s'	=> \$ldap_expected_answers,
  'format_email|fe:s'		=> \$ldap_result_email,
  'format_realname|fr:s'	=> \$ldap_result_realname,
  'format_comment|fc:s'		=> \$ldap_result_comment,
  'nickname|n=s'		=> \$ldap_server_nickname,
  'bind_dn|bd:s'                => \$ldap_bind_dn,
  'bind_password|bp:s'          => \$ldap_bind_password,
  'ssl'				=> \$ldap_ssl,
  'debug'			=> sub { $DEBUG = 1 },
  'help|?|h'			=> \$help,
  'man|m'			=> \$man,
  'ignorant|i'			=> \$ignorant,
  'lbdb_output|l'		=> \$lbdb_output,
  'version|v'			=> \$version
);

#
# print usage and help info before we process config files
#
pod2usage(1) if $help;
pod2usage(-verbose => 2) if $man;

if ($version) {
  print "mutt_ldap_query version " . &versionstring() . "\n";
  print '$Id: mutt_ldap_query.pl.in,v 1.20 2005-10-29 14:48:11 roland Exp $ ' . "\n";
  exit(0);
}

# command-line config file take precedence over command-line options
if ($config_file) {
  process_file($config_file);
}


# after we've done with GetOptions $ARGV[0] should present the rest
# (i.e. mandatory search pattern)
die pod2usage(1) if (! $ARGV[0] );

if ($ldap_server_nickname) {
  my $option_array = $ldap_server_db{$ldap_server_nickname};
  die print "$0 unknown server nickname:\n\t no server associated to the nickname $ldap_server_nickname, please modify the internal database according your needs by editing the ressource file or specifying the relevant one to use\n" if ! $option_array;
  $ldap_server = $option_array->[0];
  $search_base = $option_array->[1];
  $ldap_search_fields = $option_array->[2];
  $ldap_expected_answers = $option_array->[3];
  $ldap_result_email = $option_array->[4];
  $ldap_result_realname = $option_array->[5];
  $ldap_result_comment = $option_array->[6];
  if (defined($option_array->[7])) {
     $ignorant = $option_array->[7];
  }
  if (defined($option_array->[8])) {
     $ldap_bind_dn = $option_array->[8];
  }
  if (defined($option_array->[9])) {
     $ldap_bind_password = $option_array->[9];
  }
}

print "DEBUG: ldap_server='$ldap_server' search_base='$search_base' search_fields='$ldap_search_fields'\
       expected_answer='$ldap_expected_answers' format_email='$ldap_result_email' format_realname='$ldap_result_realname'\
       bind_dn='$ldap_bind_dn' bind_password='$ldap_bind_password'\n" if ($DEBUG);

my @fields = split / /, $ldap_search_fields;
my @results;

foreach my $askfor ( @ARGV ) {
  my $query="";
  if ($ignorant) {
# enable this if you want to include wildcard in your search with some huge
# ldap databases you might want to avoid it
    $query = join '', map { "($_=*$askfor*)" } @fields;
  }
  else {
    $query = join '', map { "($_=$askfor)" } @fields;
  }
  $query = "(|" . $query . ")";

  print "DEBUG: perl ldap module processing filter:\nDEBUG: $query\n" if ($DEBUG);
  my $ldap;
  if ($ldap_ssl) {
    $ldap = Net::LDAPS->new($ldap_server, Port=> 636, Debug => 3) or die $@;
  } else {
    $ldap = Net::LDAP->new($ldap_server, Port => 389, Debug => 3) or die $@;
  }
  if (defined($ldap_bind_dn) && $ldap_bind_dn ne ''
      && defined($ldap_bind_password) && $ldap_bind_password ne '') {
    $ldap->bind($ldap_bind_dn, password=> $ldap_bind_password);
  } else {
    $ldap->bind;
  }
  my $mesg = $ldap->search( base => $search_base, filter => $query ) or die $@;
  if ($mesg->code && ($mesg->code ne '4')) {
    die "Search failed. LDAP server returned an error : ", $mesg->code, ", description: ", $mesg->error;
  }
  my @entries = $mesg->entries;
  map { $_->dump } $mesg->all_entries if ($DEBUG);
  my $entry;
  foreach $entry (@entries) {
    print "DEBUG: processing $entry->dn\n" if ($DEBUG);
# prepare the results
    my @emails = ();
    my $realname = $ldap_result_realname;
    my $comment = $ldap_result_comment;
    foreach my $answer (split / /, $ldap_expected_answers) {
      my $result = '';
# if this is email we take all the values
      if( $ldap_result_email =~ /\${$answer}/ ) {
        @emails = $entry->get_value($answer);
      } 
      else {
        my $result = '';
# if there is no answer must return the null otherwise we get an uninitialized variable error
        ($result = $entry->get_value($answer)) || ($result = '');
# replace the containers with the results of the query
        $realname =~ s/\${$answer}/$result/g;
        $comment =~ s/\${$answer}/$result/g;
      }
    }
    foreach my $ema (@emails)  {
       push @results, "$ema\t$realname\t$comment\n";
    }
  }
  $ldap->unbind;
}

if ($lbdb_output) {
# display results convenient for lbdb processing
  print @results;
}
else {
  print "LDAP query: found ", scalar(@results), "\n", @results;
}

exit 1 if ! @results;

__END__

=head1 NAME

mutt_ldap_query - Query LDAP server for Mutt mail-reader

=head1 SYNOPSIS

mutt_ldap_query.pl [options] <name_to_query> [[<other_name_to_query>] ...]

=head1 OPTIONS

=over 8

=item B<--config=config_file> or B<-c config_file>

specify an alternate resource file other than the system ones (F</etc/lbdb_ldap.rc> or F</etc/mutt_ldap_query.rc>) or default personal ones (F<$HOME/.lbdb/ldap.rc> or F<$HOME/.mutt_ldap_query.rc>).

=item B<--ssl>

use ssl connection

=item B<--server=ldap_server> or B<-ls ldap_server>

hostname of your ldap server.

=item B<--search_base=ldap_search_base> or B<-sb ldap_search_base>

use <search_base> as the starting point for the search instead of the default.

=item B<--search_fields=ldap_search_fields> or B<-sf ldap_search_fields>

list of the fields on which the query will be performed.

=item B<--expected_answers=ldap_expected_answers> or B<-ea ldap_expected_answers>

list of the fields expected as the answer of the ldap server that will be used for composing the output of the script.

=item B<--format_email=result_format_email> or B<-fe result_format_email>

format to be used for composing the email output result. It has to be based on the expected ldap server answers and can use variable containers of the form ${variable} where variable belongs to the <ldap_expected_answers> set.

=item B<--format_realname=result_format_realname> or B<-fr result_format_realname>

format to be used for composing the realname output result. It has to be based on the expected ldap server answers and can use variable containers of the form ${variable} where variable belongs to the <ldap_expected_answers> set.

=item B<--format_comment=result_format_comment> or B<-fc result_format_comment>

format to be used for composing the comment output result. It has to be based on the expected ldap server answers and can use variable containers of the form ${variable} where variable belongs to the <ldap_expected_answers> set.

=item B<--bind_dn=bind_distinguished_name> or B<-bd bind_distinguished_name>

the destinguished name of the user who binds to the LDAP server.  Leave it empty for an anonmyous bind.

=item B<--bind_password=secret> or B<-bp secret>

the bind password for binding to the LDAP server. Leave it empty for an anonmyous bind.

=item B<--nickname=ldap_server_nickname> or B<-n ldap_server_nickname>

shortcut for avoiding to use all the previous options by using the script builtin or alternate config file table of common servers and associated options.  All the required parameters are then derived by performing a <lbdb_server_nickname> lookup.

=item B<--debug> or B<-d>

turn on debugging messages.

=item B<--help> or B<-?> or B<-h> or B<--man> or B<-m>

generates this help message.

=item B<--ignorant> or B<-i>

ignorant mode: search using wildcard for *name_to_query* (requires a longer processing from LDAP server but is quite convenient :).

=item B<--lbdb_output> or B<-l>

suppress number of matches output (suited for interfacing with little brother database http://www.spinnaker.de/lbdb/).

=item B<--version> or B<-v>

show the version.

=back

=head1 DESCRIPTION

B<mutt_ldap_query> performs ldap queries using either ldapsearch command or the perl-ldap module and it outputs the required formatted data for feeding mutt when using its "External Address Query" feature.

The output of the script consists in 3 fields separated with tabs: the email address, the name of the person and a comment.

=head1 INTERFACING WITH MUTT

This perl script can be interfaced with mutt by defining in your .muttrc:

    set query_command = "mutt_ldap_query.pl '%s'"

Multiple requests are supported: the "Q" command of mutt accepts as argument a list of queries (e.g. "Gosse de\ Courville").

Alternatively mutt_ldap_query can be interfaced with the more generic little brother database query program (http://www.spinnaker.de/lbdb/) using:

    set query_command = "lbdbq '%s'"

and by specifying in your ~/.lbdb/lbdbrc file another method of query just adding to the METHODS variable the m_ldap module e.g.:

    METHODS='m_inmail m_passwd m_ldap m_muttalias m_finger'

and the right path to access m_ldap in MODULES_PATH, e.g. if you moved F<m_ldap> in F<~/.lbdb/modules>:

    MODULES_PATH="/usr/local/lib $HOME/.lbdb/modules"

Just make sure to use the correct path for calling mutt_ldap_query in the m_ldap script.

=head1 RESOURCE FILE FORMAT

mutt_ldap_query is now fully customizable using an external resource file. By default mutt_ldap_query parses the system definition file located generally at F</etc/mutt_ldap_query.rc> or F</usr/local/etc/mutt_ldap_query.rc> and also the user one: F<$HOME/.mutt_ldap_query.rc>.

Instead of using command line options, the user can redefine all the variables using the resource file by two manners in order to match his site configuration.  A file example is provided below:

    # The format of each entry of the ldap server database is the following:
    # LDAP_NICKNAME => ['LDAP_SERVER', 
    #                   'LDAP_SEARCH_BASE',
    #                   'LDAP_SEARCH_FIELDS',
    #                   'LDAP_EXPECTED_ANSWERS',
    #                   'LDAP_RESULT_EMAIL',
    #                   'LDAP_RESULT_REALNAME',
    #                   'LDAP_RESULT_COMMENT'],
    
    # a practical illustrating example being:
    #  debian	=> ['db.debian.org',
    #               'ou=users,dc=debian,dc=org',
    #               'uid cn sn ircnick',
    #               'uid cn sn ircnick',
    #               '${uid}@debian.org',
    #               '${cn} ${sn}',
    #               '${ircnick}'],
    # the output of the query will be then: 
    # ${uid}@debian.org\t${cn} ${sn}\t${ircnick} (i.e.: email name comment)
    
    # warning this database will erase default script builtin
    %ldap_server_db = (
      'four11'		=> ['ldap.four11.com', 'c=US', 'givenname sn cn mail', 'givenname cn sn mail o', '${mail}', '${givenname} ${sn}', '${o}' ],
      'infospace'	=> ['ldap.infospace.com', 'c=US', 'givenname sn cn mail', 'givenname cn sn mail o', '${mail}', '${givenname} ${sn}', '${o}' ],
      'whowhere'	=> ['ldap.whowhere.com', 'c=US', 'givenname sn cn mail', 'givenname cn sn mail o', '${mail}', '${givenname} ${sn}', '${o}' ],
      'bigfoot'		=> ['ldap.bigfoot.com', 'c=US', 'givenname sn cn mail' , 'givenname cn sn mail o' , '${mail}' , '${givenname} ${sn}', '${o}' ],
      'switchboard'	=> ['ldap.switchboard.com', 'c=US', 'givenname sn cn mail' , 'givenname cn sn mail o', '${mail}', '${givenname} ${sn}', '${o}' ],
      'infospacebiz'	=> ['ldapbiz.infospace.com', 'c=US', 'givenname sn cn mail', 'givenname cn sn mail o', '${mail}', '${givenname} ${sn}', '${o}' ],
    );
    
    # hostname of your ldap server
    $ldap_server = 'ldap.four11.com';
    # ldap base search
    $search_base = 'c=US';
    # list of the fields that will be used for the query
    $ldap_search_fields = 'givenname sn cn mail';
    # list of the fields that will be used for composing the answer
    $ldap_expected_answers = 'givenname sn cn mail o';
    # format of the email result based on the expected answers of the ldap query
    $ldap_result_email = '${mail}';
    # format of the realname result based on the expected answers of the ldap query
    $ldap_result_realname = '${givenname} ${sn}';
    # format of the comment result based on the expected answers of the ldap query
    $ldap_result_comment = '(${o})';

=head1 EXAMPLES OF QUERIES

    mutt_ldap_query.pl --ldap_server='ldap.mot.com' --search_base='ou=employees, o=Motorola,c=US' --ldap_search_fields='commonName gn sn cn uid' --ldap_expected_answers='gn sn preferredRfc822Recipient ou c telephonenumber' --ldap_result_email='${preferredRfc822Recipient}' --ldap_result_realname='${gn} ${sn}' --ldap_result_comment='(${telephonenumber}) ${ou} ${c}' Gosse de\ Courville

performs a query using the ldap server ldap.mot.com using the following searching base 'ou=employees, o=Motorola,c=US' and performing a search on the fields 'commonName gn sn cn uid' for 'Gosse' and then "de Courville" looking for the following answers 'gn sn preferredRfc822Recipient ou c telephonenumber'. Based on this answers, mutt_ldap_query will return a list of entries identified of the form:

  <${preferredRfc822Recipient}>\t${gn} ${sn}\t(${telephonenumber}) ${ou} ${c}

where ${} variables should be considered as containers that are replaced by the results of the query. The previous query can be greatly simplified by using the ldap server mini database feature of the resource file introducing for example a nickname.

    mutt_ldap_query.pl --ldap_server_nickname='motorola' Gosse de\ Courville

When not sure of the full name (i.e. it should contain Courville) the ignorant mode is useful since the query will be performed using wildcards, i.e. *Courville* in the following case:

    mutt_ldap_query.pl --ignorant Courville

=head1 WHERE TO GET IT

The latest version can be retrieved at ftp://ftp.mutt.org/pub/mutt/contrib or http://www.courville.org/

Note that now the script is integrated in the latest version of the little brother database available at http://www.spinnaker.de/lbdb/.  It is thus easier to use through this standard package than to hand customize it to fit your system/distribution needs.

=head1 REFERENCES

=over 2

=item -

perl-ldap module http://perl-ldap.sourceforge.net/

=item -

mutt is the ultimate email client http://www.mutt.org/

=item -

historical Brandon Blong's "External Address Query" feature patch for mutt http://www.fiction.net/blong/programs/mutt/#query

=item -

little brother database is an interface query program for mutt that allow multiple searches for email addresses based on external query scripts just like this one 8-) http://www.spinnaker.de/lbdb/

=head1 AUTHORS

Marc de Courville <marc@courville.org> and the various other contributors... that kindly sent their patches.

Please report any bugs, or post any suggestions, to <marc@courville.org>.

=head1 COPYRIGHT

Copyright (c) 1998-2003 Marc de Courville <marc@courville.org>. All rights reserved. This program is free software; you can redistribute it and/or modify it under the GNU General Public License (GPL). See http://www.opensource.org/gpl-license.html and http://www.opensource.org/.

=cut
