output "zone_id" {
  description = "The Cloudflare zone ID"
  value       = data.cloudflare_zone.this.id
}

output "record_hostnames" {
  description = "Map of record name to fully-qualified hostname"
  value       = { for k, v in cloudflare_record.records : k => v.hostname }
}
