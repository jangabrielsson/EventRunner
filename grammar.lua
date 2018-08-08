
<symbol> ::= (a-zA-Z) (a-zA-Z_0-9)
<global> ::= !<symbol> 
<var> ::= <symbol>
<constant> ::= 'now' | 'midnight' | 'sunrise' | 'sunset' | 'true' | 'false' | 'nil' | '{}' 
<oper> ::= + | - | * | / | "|" | & | > | < | >= | <= | == | = | =~ | = | .. | .| : 
<expr> ::= <table> | <call> | <event> | <num> | <string> | <constant> | <var> | <global> | <time> | <addr>
<expr> ::= <expr> <oper> <expr> | - <expr> | ( <expr> )
<expr> ::= fn(<var>,...,<var>) -> <statements> end
<expr> ::= <expr>[<expr>]
<expr> ::= <expr> ? <expr> : <expr>
<call> ::= <fun>(<expr>, ..., <expr>) | <var>(<expr>, ..., <expr>) | (<expr>)(<expr>, ..., <expr>)
<statements> ::= statement [ ; <statements> ]
<statement> ::= <expr>
<statement> ::= || <expr> >> <statements> {|| <expr> >> <statements>} [;;]
<cmd> ::= <expr> | <expr> => <statements> | def <var>(<var>,...,<var>) -> <statements> end

room.lamp.on

aref(aref(room,lamp),on)