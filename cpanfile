requires 'perl', '5.020';
requires 'HTTP::Message';
requires 'IO::Socket::SSL';
requires 'JSON::MaybeXS';
requires 'LWP::Protocol::https';
requires 'LWP::UserAgent';
requires 'Moo';
requires 'Type::Tiny';
requires 'namespace::autoclean', '0.16';

on test => sub {
    requires 'Test::More', '0.96';
    requires 'URI';
};
