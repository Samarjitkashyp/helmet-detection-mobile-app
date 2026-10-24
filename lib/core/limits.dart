/// The server sits behind Cloudflare, which rejects request bodies over 100 MB, so the backend caps uploads at 95 MB.
const int maxUploadMb = 95;

/// 5 Mbps keeps a full 2-minute 1080p clip near 75 MB (under the cap) and is plenty for detection.
const int recordVideoBitrate = 5000000;
