enum Token<'a> {
    LSqBracket,
    RSqBracket,
    Semicolon,
    Identifier(&'a str),
    Integer(usize),
}

pub struct TokenIter<'a> {
    remaining: &'a str
}

impl<'a> TokenIter<'a> {
    pub fn new(str: &'a str) -> Self {
        Self {
            remaining: str
        }
    }
}

//impl Iterator for TokenIter {
//
//}
