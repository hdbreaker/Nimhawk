#[
    Port: StringObfuscationPort
    Outbound port for string obfuscation functionality
    Allows domain/application layers to obfuscate strings without depending on infrastructure
]#

type
    StringObfuscationPort* = concept obfuscator
        ## Port for string obfuscation
        ## Implementations should provide obfuscation functionality
        
        proc obfuscate*(obfuscator: obfuscator, s: string): string
            ## Obfuscate a string
            ## Returns obfuscated string

