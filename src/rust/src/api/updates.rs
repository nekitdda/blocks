#[derive(Debug, Clone)]
pub struct AppUpdateInfoDto {
    pub latest_version: String,
    pub changelog: String,
    pub url: String,
    pub has_update: bool,
}

fn is_newer_version(current: &str, latest: &str) -> bool {
    // `2.7.0-beta1` used to parse as [2,7,0] because the `-beta1` suffix was
    // never stripped, so a prerelease was offered as a normal update. Compare
    // the numeric core, then apply the semver rule that a prerelease sorts
    // *below* the same numeric release.
    let split = |v: &str| -> (Vec<i64>, Option<String>) {
        let mut cleaned = v.trim().to_lowercase();
        if cleaned.starts_with('v') {
            cleaned.remove(0);
        }
        if let Some(pos) = cleaned.find('+') {
            cleaned.truncate(pos);
        }
        let (core, pre) = match cleaned.split_once('-') {
            Some((core, pre)) => (core, Some(pre.to_string())),
            None => (cleaned.as_str(), None),
        };
        // `unwrap_or(0)` also keeps a pathological "999...9" from overflowing:
        // `parse::<i64>()` returns Err rather than wrapping.
        let parts = core
            .split('.')
            .map(|s| s.parse::<i64>().unwrap_or(0))
            .collect();
        (parts, pre)
    };

    let (cur_parts, cur_pre) = split(current);
    let (lat_parts, lat_pre) = split(latest);

    let max_len = std::cmp::max(cur_parts.len(), lat_parts.len());
    for i in 0..max_len {
        let cur_val = *cur_parts.get(i).unwrap_or(&0);
        let lat_val = *lat_parts.get(i).unwrap_or(&0);
        if lat_val > cur_val {
            return true;
        }
        if lat_val < cur_val {
            return false;
        }
    }

    // Same numbers: 2.7.0-beta1 < 2.7.0, and 2.7.0 > 2.7.0-beta1. A prerelease is
    // only "newer" than another prerelease with a higher identifier.
    match (cur_pre, lat_pre) {
        (_, None) => true,           // release > any prerelease of the same version
        (None, Some(_)) => false,    // we are on the release, nothing to upgrade to
        (Some(a), Some(b)) => b > a,
    }
}

pub async fn check_for_updates() -> Option<AppUpdateInfoDto> {
    // Shared client + a timeout: `reqwest` has no default request timeout, so
    // this could hang for minutes on a stalled connection, and building a fresh
    // client (plus connection pool) per call wasted resources. The GitHub API
    // also allows only 60 unauthenticated requests/hour/IP, so toggling the
    // setting repeatedly returned None with no way to tell it apart from
    // "already up to date".
    static CLIENT: std::sync::LazyLock<reqwest::Client> = std::sync::LazyLock::new(|| {
        reqwest::Client::builder()
            .user_agent("youmuz-app")
            .timeout(std::time::Duration::from_secs(10))
            .build()
            .unwrap_or_default()
    });

    let res = CLIENT
        .get("https://api.github.com/repos/DarkPlayOff/YouMuz/releases/latest")
        .header("Accept", "application/vnd.github.v3+json")
        .send()
        .await
        .ok()?;

    if !res.status().is_success() {
        return None;
    }

    #[derive(serde::Deserialize)]
    struct GithubRelease {
        tag_name: String,
        body: Option<String>,
        html_url: String,
    }

    let release: GithubRelease = res.json().await.ok()?;
    let current_version = crate::api::simple::get_app_version();
    let has_update = is_newer_version(&current_version, &release.tag_name);

    Some(AppUpdateInfoDto {
        latest_version: release.tag_name,
        changelog: release.body.unwrap_or_default(),
        url: release.html_url,
        has_update,
    })
}
