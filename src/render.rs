use std::ffi::c_char;

use crate::{
    features::VkFeatureGuard,
    scene::Scene,
    utils::{QueueFamilyInfo, QueueInfo},
};
use ash::{Device, Entry, Instance};

pub mod renderers;

// Device should be initialized outside the renderer, but renderer takes device for construction

pub trait Renderer<S, Target>
where
    S: Scene,
{
    type Error;

    fn new(vk_lib: &Entry, instance: &Instance, device: &Device, queue_info: QueueInfo) -> Self;

    fn ingest_scene(&mut self, scene: &S);
    fn render_to(&mut self, updates: S::Updates, target: &mut Target) -> Result<(), Self::Error>;

    fn required_instance_extensions() -> &'static [*const c_char];
    fn required_device_extensions() -> &'static [*const c_char];
    fn required_features() -> VkFeatureGuard<'static>;

    fn has_required_queue_families(queue_family_info: &QueueFamilyInfo) -> bool;
    fn get_queue_info(queue_family_info: &QueueFamilyInfo) -> QueueInfo;
}
