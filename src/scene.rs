pub mod scenes;
pub mod type_lexer;

pub trait Scene {
    type Update: Sized;
}
