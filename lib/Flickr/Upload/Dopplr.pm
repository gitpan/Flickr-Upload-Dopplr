# $Id: Dopplr.pm,v 1.10 2007/09/13 14:50:29 asc Exp $

use strict;

package FUDException;
use base qw (Error);

# http://www.perl.com/lpt/a/690

use overload ('""' => 'stringify');

sub new {
    my $self = shift;
    my $text = shift;
    my $prev = shift;

    if (UNIVERSAL::can($prev, "stacktrace")){
            $text .= "\n";
            $text .= $prev->stacktrace();
    }

    local $Error::Depth = $Error::Depth + 1;
    local $Error::Debug = 1;  # Enables storing of stacktrace

    $self->SUPER::new(-text => $text);
}

sub stringify {
        my $self = shift;
        my $pkg = ref($self) || $self;
        return sprintf("[%s] %s", $pkg, $self->stacktrace());
}

package FlickrUploadException;
use base qw (FUDException);

package FlickrAPIException;
use base qw (FUDException);

sub new {
        my $pkg = shift;
        my $text = shift;
        my $prev = shift;
        my $code = shift;
        my $msg = shift;

        $text .= " Error code $code";

        my $self = $pkg->SUPER::new($text, $prev);

        $self->{'api_error_code'} = $code;
        $self->{'api_error_message'} = $msg;
        return $self;
}

sub error_code {
        my $self = shift;
        return $self->{'api_error_code'};
}

sub error_message {
        my $self = shift;
        return $self->{'api_error_message'};
}

package NetDopplrException;
use base qw (FUDException);

package Flickr::Upload::Dopplr;
use base qw (Flickr::Upload);

$Flickr::Upload::Dopplr::VERSION = '0.1';

=head1 NAME

Flickr::Upload::Dopplr - Flickr::Upload subclass to assign location information using Dopplr

=head1 SYNOPSIS

 use Flickr::Upload::Dopplr;

 my %dp_args = ('auth_token' => 'JONES!!!!',
                'tagify' => 'delicious');

 my %fl_args = ('key' => 'OH HAI',
                'secret' => 'OH NOES',,
                'dopplr' => \%dp_args);

 my $uploadr = Flickr::Upload::Dopplr->new(\%fl_args);

 my $photo_id = $uploadr->upload('photo' => "/path/to/photo",
                                 'auth_token' => 'O RLY');

=head1 DESCRIPTION

A Flickr::Upload subclass to assign location information using Dopplr.

Specifically, the package will query Dopplr for the current location of the
user associated with I<$dopplr_authtoken> and assign the city name as a tag
and a machinetag with the Geonames.org ID for that city.

If the Dopplr API thinks that it is a "travel day" another machine tag (dopplr:trip=)
will be added containing the numeric identifier for that trip.

If the package is able to query a photo's EXIF data and read the I<DateTimeOriginal>
field that value will be used to query Dopplr for your location on that day.

If an upload is successful, the package will attempt to assign latitude and
longitude information for the photo with a Flickr accuracy of 11 (or "city") and,
optionally, set geo permissions specific to that photo.

=head1 ERROR HANDLING

Flickr::Upload::Dopplr uses Error.pm to catch and throw exceptions. Although
this is still a mostly un-Perl-ish way of doing things, it seemed like the most sensible
way to handle the variety of possible error conditions. I don't love it but we'll see.

This means that the library B<will throw fatal exceptions> and you will need to
code around it using either I<eval> or - even better - I<try> and I<catch> blocks.

There are four package-specific exception handlers :

=over 4

=item * B<FUDException>

An error condition specific to I<Flickr::Upload::Dopplr> was triggered.

=item * B<FlickrUploadException>

An error condition specific to I<Flickr::Upload> was triggered.

=item * B<FlickrAPIException>

An error condition specific to calling the Flickr API (read : I<Flickr::API>)
was triggered.

This is the only exception handler that defines its own additional methods. They
are :

=over 4

=item * B<error_code>

The numeric error code returned by the Flickr API.

=item * B<error_message>

The textual error message returned by the Flickr API.

=back

=item * B<NetDopplrException>

An error condition specific to I<Net::Dopplr> was triggered.

=back

=head1 CAVEATS

=over 4

=item *

Asynchronous uploads are not support and will trigger an exception.

=item * 

At the moment, the package does not check to see whether geo information was
already assigned (for example, via GPS EXIF data). This will be fixed in future
releases.

=back

=cut

use Net::Dopplr;
use Image::Info qw (image_info);
use Error qw(:try);

$Error::Debug = 1;

=head1 PACKAGE METHODS

=head2 __PACKAGE__->new(\%args)

All the same arguments required by the I<Flickr::Upload> constructor plus the
following :

=over 4

=item * B<dopplr>

A hash reference containing the following keys :

=over 4

=item * B<auth_token>

String. I<required>

A valid Dopplr API authentication token.

=item * B<tagify>

String.

An optional flag to format tags for cities, specific to a service. Valid
services are :

=over 4 

=item * B<delicious>

City names are lower-cased and spaces are removed.

=item * B<flickr>

City names are wrapped in double-quotes if they contain spaces.

=back

The default value is I<flickr>

=back

=back

Returns a I<Flickr::Upload::Dopplr> object.

=cut

sub new {
        my $pkg = shift;
        my $args = shift;

        my $dargs = $args->{'dopplr'};
        delete($args->{'dopplr'});

        my $self = undef;

        try {
                $self = $pkg->SUPER::new($args);
        }
        
        catch Error with {
                my $e = shift;
                throw FlickrUploadException("Failed to instantiate Flickr::Upload", $e);
        };

        my $token = $dargs->{'auth_token'};

        try {
                $self->{'__dopplr'} = Net::Dopplr->new($token);
        }
         
        catch Error with {
                my $e = shift;
                throw NetDopplrException("Failed to instantiate Net::Dopplr", $e);
        };

        $self->{'__dargs'} = $dargs;

        return $self;
}

=head1 OBJECT METHODS YOU SHOULD CARE ABOUT

=head2 $obj->upload(%args)

Nothing you wouldn't pass the Flickr::Upload I<upload> method.

Except for the part where the I<async> flag which is not honoured. I'm working
on it.

In additional, you may pass an optional I<geo> parameter. It must be a hash
reference with the following keys :

=over 4

=item * B<perms>

Itself a hash reference containing is_public, is_contact, is_family and is_friend
keys and their boolean values to set the geo permissions on your uploaded photo.

If this is not defined then your default viewing settings for geo data will be left
in place.

=back

Returns a photo ID!

=cut

sub upload {
        my $self = shift;
        my %args = @_;

        if ($args{'async'}){
                throw FUDException("Asynchronous uploads are not supported yet");
        }
        
        #

        my $city = undef;
        my $id = 0;
        my $geo = undef;

        if (ref($args{'geo'}) eq "HASH"){
                $geo = $args{'geo'};
                delete($args{'geo'});
        }

        #

        $city = $self->where_am_i($args{'photo'});
        
        if (! $city){
                throw FUDException("No city data returned from Dopplr");
        }

        $args{'tags'} .= sprintf(" \"%s\"", $self->tagify($city->{'name'}));
        $args{'tags'} .= sprintf(" geonames:locality=%d", $city->{'geoname_id'});
        
        if ($city->{'tripid'}){
                $args{'tags'} .= sprintf(" dopplr:trip=%d", $city->{'tripid'});
        }       

        try {
                $id = $self->SUPER::upload(%args);
        }

        catch Error with {
                throw FlickrUploadException("Failed to upload photo to Flickr", shift);                
        };

        if (! $id){
                throw FlickrUploadException("Flickr::Upload did not return a photo ID");
        }

        # 

        my %set = ('accuracy' => 11,
                   'lat' => $city->{'latitude'},
                   'lon' => $city->{'longitude'},
                   'auth_token' => $args{'auth_token'},
                   'photo_id' => $id);

        $self->flickr_api_call('flickr.photos.geo.setLocation', \%set);
        
        #

        if (exists($geo->{'perms'})){

                my %perms = %{$geo->{'perms'}};
                $perms{'auth_token'} = $args{'auth_token'};
                $perms{'photo_id'} = $id;

                if ($perms{'is_public'}){
                        foreach my $other ('is_contact', 'is_family', 'is_friend'){
                                if (! exists($perms{$other})){
                                        $perms{$other} = 1;
                                }
                        }
                }

                $self->flickr_api_call('flickr.photos.geo.setPerms', \%perms);
        }

        #

        return $id;
}

sub where_am_i {
        my $self = shift;
        my $photo = shift;

        if (my $when = $self->when_was_that($photo)){
                return $self->where_was_i_then($when);
        }
        
        return $self->where_am_i_now();
}

sub where_was_i_then {
        my $self = shift;
        my $ymd = shift;

        my $info = undef;

        try {
                $info = $self->{'__dopplr'}->location_on_date('', 'date' => $ymd);
        }

        catch Error with {
                throw NetDopplrException("Failed to call location_on_date", shift);
        };

        if (! $info){
                return undef;
        }

        my $city = $info->{'location'}->{'home'};

        if ($info->{'location'}->{'trip'}){
                $city = $info->{'location'}->{'trip'}->{'city'};
                $city->{'tripid'} = $info->{'location'}->{'trip'}->{'id'};
        }

        return $city;
}

sub where_am_i_now {
        my $self = shift;
        my $info = undef;

        try {
                $info = $self->{'__dopplr'}->traveller_info();
        }

        catch Error with {
                throw NetDopplrException("Failed to call traveller_info", shift);
        };

        if (! $info){
                return undef;
        }
        
        my $city = $info->{'traveller'}->{'current_city'};

        if ($info->{'traveller'}->{'travel_today'}){
                $city->{'tripid'} = $info->{'traveller'}->{'current_trip'}->{'id'};
        }

        return $city;
}

sub when_was_that {
        my $self = shift;
        my $photo = shift;

        my $info = undef;

        eval {
                $info = image_info($photo);
        };

        if (($info) && ($info->{'DateTimeOriginal'})){
                if ($info->{'DateTimeOriginal'} =~ /^(\d{4})[\:-](\d{2})[\:-](\d{2})/){
			return join("-", $1, $2, $3);
		}
        }

        return undef;
}

#
# Please for someone to write Text::Tagify...
#

sub tagify {
	my $self = shift;
        my $tag = shift;

        if ($self->{'__dargs'}->{'tagify'} eq "delicious"){
                return $self->tagify_like_delicious($tag);
        }

        return $self->tagify_like_flickr($tag);
}

sub tagify_like_flickr {
        my $self = shift;
        my $tag = shift;

        if ($tag =~ /\s/){
                $tag = "\"$tag\"";
        }

        return $tag;
}

sub tagify_like_delicious {
        my $self = shift;
        my $tag = shift;

        $tag =~ s/\s//g;
        return lc($tag);
}

sub flickr_api_call {
        my $self = shift;
        my $meth = shift;
        my $args = shift;

        my $res;

        try {
                $res = $self->execute_method($meth, $args);
        }
                
        catch Error with {
                my $e = shift;
                throw FlickrAPIException("API call $meth failed", 999, "Unknown API error");
        };

        if (! $res->{success}){
                my $e = shift;
                throw FlickrAPIException("API call $meth failed", $e, $res->{error_code}, $res->{error_message});
        }

        return $res;
}


=head1 VERSION

0.1

=head1 DATE

$Date: 2007/09/13 14:50:29 $

=head1 AUTHOR

Aaron Straup Cope <ascope@cpan.org>

=head1 SEE ALSO

L<Flickr::API>

L<Flickr::Upload>

L<Net::Dopplr>

L<Error>

L<http://www.aaronland.info/weblog/2007/08/24/aware/#reduced>

=head1 BUGS

Please report all bugs via http://rt.cpan.org/

=head1 LICENSE

Copyright (c) 2007 Aaron Straup Cope. All Rights Reserved.

This is free software. You may redistribute it and/or
modify it under the same terms as Perl itself.

=cut

return 1;
