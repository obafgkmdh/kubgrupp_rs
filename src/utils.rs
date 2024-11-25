use anyhow::Result;
use ash::{khr, vk, Entry, Instance};

// it is fine to make DeviceQueueCreateInfo lifetime static because we are not using any of the p_next stuff
// if we need to use those, then this kinda becomes a problem lul
// honestly i dont really like how we have to basically just pass around the queueinfo to the renderer when literally only
// the renderer cares about it
// it seems like maybe there should be some subcomponent of the renderer thats responsible for device creation instead
// i love abstractions i love abstractions i love abstractions
pub struct QueueInfo {
    pub infos: Vec<vk::DeviceQueueCreateInfo<'static>>,
}

#[derive(Default, Clone)]
pub struct QueueFamilyInfo {
    pub graphics_index: Option<u32>,
    pub present_index: Option<u32>,
    pub compute_index: Option<u32>,
    pub transfer_index: Option<u32>,
}

pub fn query_queue_families(
    vk_lib: &Entry,
    instance: &Instance,
    device: vk::PhysicalDevice,
    surface: vk::SurfaceKHR,
) -> Result<QueueFamilyInfo> {
    let queue_families = unsafe { instance.get_physical_device_queue_family_properties(device) };
    let mut info = QueueFamilyInfo::default();

    let surface_loader = khr::surface::Instance::new(vk_lib, instance);

    // this currently just chooses the first available queue family for each thing
    // possibly suboptimal idk, but oh well
    for (i, family) in queue_families.iter().enumerate() {
        if info.graphics_index.is_none() && family.queue_flags.contains(vk::QueueFlags::GRAPHICS) {
            info.graphics_index = Some(i as u32);
        }
        if info.compute_index.is_none() && family.queue_flags.contains(vk::QueueFlags::COMPUTE) {
            info.compute_index = Some(i as u32);
        }
        if info.transfer_index.is_none() && family.queue_flags.contains(vk::QueueFlags::TRANSFER) {
            info.compute_index = Some(i as u32);
        }

        let present_support = unsafe {
            surface_loader.get_physical_device_surface_support(device, i as u32, surface)
        }?;
        if info.present_index.is_none() && present_support {
            info.present_index = Some(i as u32);
        }
    }

    Ok(info)
}
