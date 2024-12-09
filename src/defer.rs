use std::{fmt::Debug, ops::Deref};

pub struct Deferred<T, F>
where
    F: FnMut(&T),
{
    inner: Option<T>,
    func: F,
}

impl<T, F: FnMut(&T)> Deferred<T, F> {
    /// Returns the stored inner `T` and "cancels" the deferred closure
    pub fn undefer(mut self) -> T {
        self.inner.take().unwrap()
    }
}

impl<T, F: FnMut(&T)> Deref for Deferred<T, F> {
    type Target = T;

    fn deref(&self) -> &Self::Target {
        self.inner.as_ref().unwrap()
    }
}

impl<T, F: FnMut(&T)> Drop for Deferred<T, F> {
    fn drop(&mut self) {
        if let Some(inner) = &self.inner {
            (self.func)(inner)
        }
    }
}

impl<T: Debug, F: FnMut(&T)> Debug for Deferred<T, F> {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        // unwrap the option, since deferred should never be able to exist with the None variant unless it is currently being dropped
        let inner = self
            .inner
            .as_ref()
            .expect("this should be impossible to see - if you see this, something has gone wrong");
        f.debug_struct("Deferred")
            .field("inner", &inner)
            .finish_non_exhaustive()
    }
}

pub trait Defer {
    type Target;

    fn defer<F: FnMut(&Self::Target)>(self, func: F) -> Deferred<Self::Target, F>;
}

impl<T> Defer for T {
    type Target = T;

    fn defer<F: FnMut(&Self::Target)>(self, func: F) -> Deferred<Self::Target, F> {
        Deferred {
            inner: Some(self),
            func,
        }
    }
}
