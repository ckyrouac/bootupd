use camino::{Utf8Path, Utf8PathBuf};
use std::path::Path;

use anyhow::{Context, Result};
use fn_error_context::context;

use bootc_internal_blockdev::list_dev_by_dir;
use cap_std_ext::cap_std;

#[context("get parent devices from mount point boot or sysroot")]
pub fn get_devices<P: AsRef<Path>>(target_root: P) -> Result<Vec<String>> {
    let cap_sysroot =
        cap_std::fs::Dir::open_ambient_dir(target_root, cap_std::ambient_authority())
            .context("Opening root dir")?;
    let device = list_dev_by_dir(&cap_sysroot)?;
    let parent_devices = device
        .find_all_roots()?
        .iter()
        .map(|d| d.path())
        .collect();
    Ok(parent_devices)
}

/// Find all ESP partitions on the devices
/// TODO: the bootc_internal_blockdev crate can be used to do this
// pub fn find_colocated_esps(devices: &Vec<String>) -> Result<Option<Vec<String>>> {
//     // look for all ESPs on those devices
//     let mut esps = Vec::new();
//     for device in devices {
//         if let Some(esp) = get_esp_partition(&device)? {
//             esps.push(esp)
//         }
//     }
//     if esps.is_empty() {
//         return Ok(None);
//     }
//     log::debug!("Found esp partitions: {esps:?}");
//     Ok(Some(esps))
// }

