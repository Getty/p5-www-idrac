requires 'perl', '5.020';
requires 'File::Temp';
requires 'HTTP::Message';
requires 'IO::Pty';
requires 'IO::Socket::SSL';
requires 'JSON::MaybeXS';
requires 'LWP::Protocol::https';
requires 'LWP::UserAgent';
requires 'Moo';
requires 'namespace::autoclean', '0.16';
requires 'Net::OpenSSH';
requires 'Type::Tiny';

on test => sub {
    requires 'Test::More', '0.96';
    requires 'URI';
};
