#[
    Adapter: StringObfuscationAdapter
    Implements StringObfuscationPort using infrastructure/util/strenc
    Re-exports the obf macro from strenc to provide access through adapter layer
    Note: Since obf is a compile-time macro, we re-export it directly
]#

# Re-export the obf macro from infrastructure/util/strenc
# This makes it clear that string obfuscation comes through the adapter layer
# even though it's a compile-time macro dependency
from ../util/strenc import obf

# Re-export for use in application layer
export obf

