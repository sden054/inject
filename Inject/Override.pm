# Set package
package Inject::Override;

# Make aliases for variables
our $TEST_DATA = ();
*TEST_DATA = *Inject::TEST_DATA;

# Modules
use base qw(Tie::Handle);
use Symbol qw(geniosym);

# Tie
sub TIEHANDLE { return bless geniosym, __PACKAGE__ }

# Hijacked print function
sub PRINT {
	shift;
	
	if($TEST_DATA->{capture} == 1) {
		$TEST_DATA->{data} .= join('', @_);
	}

	print $OLD_STDOUT join('', @_);
}

# Tie handle
tie *PRINTOUT, 'Inject::Override';
our $OLD_STDOUT = select( *PRINTOUT );

1;
__END__

