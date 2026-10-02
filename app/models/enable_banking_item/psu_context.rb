require "ipaddr"

# User presence belongs to the request that started a sync, not to the bank
# connection. Expire it if the job was delayed; never reuse an authorization IP.
class EnableBankingItem::PsuContext
  MAX_AGE = 5.minutes
  HEADER_NAMES = %w[Psu-Ip-Address Psu-User-Agent].freeze

  def self.capture(request:, family:)
    headers = { "Psu-User-Agent" => request.user_agent.to_s.delete("\r\n").first(1024) }
    ip = IPAddr.new(request.remote_ip) rescue nil
    if ip && !ip.loopback? && !ip.private? && !ip.link_local?
      headers["Psu-Ip-Address"] = ip.to_s
    end

    {
      "family_id" => family.id,
      "requested_at" => Time.current.to_i,
      "headers" => headers.compact_blank
    }
  end

  def self.headers_for(context, family_id:, required_headers:)
    return {} unless context.is_a?(Hash)

    context = context.with_indifferent_access
    return {} unless context[:family_id].to_s == family_id.to_s

    requested_at = Integer(context[:requested_at], exception: false)
    return {} unless requested_at && (Time.current.to_i - requested_at).between?(0, MAX_AGE.to_i)
    return {} unless context[:headers].is_a?(Hash)

    headers = context[:headers].slice(*HEADER_NAMES).compact_blank
    available = headers.keys.map(&:downcase)
    return {} unless Array(required_headers).all? { |name| available.include?(name.downcase) }

    headers.to_h
  end
end
