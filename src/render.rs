use std::ffi::c_char;

use crate::{
    features::VkFeatureGuard,
    scene::Scene,
    utils::{QueueFamilyInfo, QueueInfo},
};
use ash::{vk, Device, Entry, Instance};

pub mod renderers;

// Device should be initialized outside the renderer, but renderer takes device for construction

pub trait Renderer<S, Target>
where
    S: Scene,
    Self: Sized,
{
    fn new(
        vk_lib: &Entry,
        instance: &Instance,
        device: &Device,
        physical_device: vk::PhysicalDevice,
        queue_family_info: &QueueFamilyInfo,
    ) -> anyhow::Result<Self>;

    fn ingest_scene(&mut self, scene: &S) -> anyhow::Result<()>;
    fn render_to(&mut self, updates: &S::Updates, target: &mut Target) -> anyhow::Result<()>;

    fn required_instance_extensions() -> &'static [*const c_char];
    fn required_device_extensions() -> &'static [*const c_char];
    fn required_features() -> VkFeatureGuard<'static>;

    fn has_required_queue_families(queue_family_info: &QueueFamilyInfo) -> bool;
    fn get_queue_info(queue_family_info: &QueueFamilyInfo) -> QueueInfo;
}
