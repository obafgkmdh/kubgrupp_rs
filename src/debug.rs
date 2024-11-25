use anyhow::Result;
use std::ffi::{c_void, CStr};

use ash::{
    ext,
    vk::{
        self, DebugUtilsMessageSeverityFlagsEXT, DebugUtilsMessageTypeFlagsEXT,
        DebugUtilsMessengerCallbackDataEXT, DebugUtilsMessengerCreateInfoEXT,
        DebugUtilsMessengerEXT,
    },
};
use log::{debug, error, info, warn};

pub struct DebugUtilsData {
    loader: ext::debug_utils::Instance,
    messenger: DebugUtilsMessengerEXT,
}

impl DebugUtilsData {
    pub unsafe fn new(
        loader: ext::debug_utils::Instance,
        create_info: &DebugUtilsMessengerCreateInfoEXT,
    ) -> Result<Self> {
        let messenger = loader.create_debug_utils_messenger(create_info, None)?;

        Ok(Self { loader, messenger })
    }
}

impl Drop for DebugUtilsData {
    fn drop(&mut self) {
        unsafe {
            self.loader
                .destroy_debug_utils_messenger(self.messenger, None)
        };
    }
}

pub unsafe extern "system" fn debug_callback(
    severity: DebugUtilsMessageSeverityFlagsEXT,
    msg_type: DebugUtilsMessageTypeFlagsEXT,
    callback_data: *const DebugUtilsMessengerCallbackDataEXT<'_>,
    _user_data: *mut c_void,
) -> u32 {
    let callback_data = &*callback_data;
    if callback_data.p_message.is_null() {
        return vk::FALSE;
    }

    let message = CStr::from_ptr(callback_data.p_message).to_string_lossy();

    // go in order of priority
    if severity.contains(DebugUtilsMessageSeverityFlagsEXT::ERROR) {
        error!("({:?}) {}", msg_type, message);
    } else if severity.contains(DebugUtilsMessageSeverityFlagsEXT::WARNING) {
        warn!("({:?}) {}", msg_type, message);
    } else if severity.contains(DebugUtilsMessageSeverityFlagsEXT::INFO) {
        info!("({:?}) {}", msg_type, message);
    } else if severity.contains(DebugUtilsMessageSeverityFlagsEXT::VERBOSE) {
        debug!("({:?}) {}", msg_type, message);
    } else {
        info!("(UNKNOWN_SEVERITY) ({:?}) {}", msg_type, message);
    }

    vk::FALSE
}
