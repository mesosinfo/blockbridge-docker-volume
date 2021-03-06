# Copyright (c) 2015-2017, Blockbridge Networks LLC.  All rights reserved.  Use
# of this source code is governed by a BSD-style license, found in the LICENSE
# file.

module Blockbridge
  class VolumeCacheMonitor
    include Helpers
    attr_reader :config
    attr_reader :logger
    attr_reader :status
    attr_reader :cache_version
    attr_reader :api_status
    attr_reader :api_syndrome

    def self.cache
      @@cache
    end

    def initialize(address, port, config, status, logger)
      @config = config
      @logger = logger
      @status = status
      @@cache = self
    end

    def monitor_interval_s
      ENV['BLOCKBRIDGE_MONITOR_INTERVAL_S'] || 10
    end

    def status_interval_s
      ENV['BLOCKBRIDGE_STATUS_INTERVAL_S'] || 15
    end

    def run
      EM::Synchrony.run_and_add_periodic_timer(status_interval_s, &method(:volume_api_status))
      EM::Synchrony.run_and_add_periodic_timer(monitor_interval_s, &method(:volume_cache_monitor_run))
    end

    def reset
      @cache_version = nil
    end

    def volume_invalidate(name)
      logger.info "#{name} removing stale volume from docker"
      vol_cache_enable(name)
      defer do
        docker_volume_rm(name)
      end
      vol_cache_rm(name)
      logger.info "#{name} cache invalidated."
    rescue => e
      vol_cache_disable(name)
      logger.error "Failed to remove docker cached volume: #{name}: #{e.message}"
    end

    def cache_status_create
      xmd = bbapi.xmd.info(vol_cache_ref) rescue nil
      return xmd unless xmd.nil?
      bbapi.xmd.create(ref: vol_cache_ref)
    rescue Blockbridge::Api::ConflictError
    end

    def cache_version_lookup
      xmd = cache_status_create
      xmd[:seq]
    rescue Excon::Errors::NotFound, Excon::Errors::Gone, Blockbridge::NotFound, Blockbridge::Api::NotFoundError
    end

    def volume_async_remove(vol, vol_info, vol_env)
      if vol_info
        return unless vol_info[:deleted]
        return unless ((Time.now.tv_sec - vol_info[:deleted]) > monitor_interval_s)
        raise Blockbridge::VolumeInuse if bb_get_attached(vol[:name], vol[:user], vol_info[:scope_token])
        bb_remove_vol(vol[:name], vol[:user], vol_info[:scope_token])
      end
      vol_cache_rm(vol[:name])
      logger.info "#{vol[:name]} async removed"
    rescue Excon::Errors::NotFound, Excon::Errors::Gone, Blockbridge::NotFound, Blockbridge::Api::NotFoundError
      logger.debug "#{vol[:name]} async remove: volume not found"
    rescue Blockbridge::VolumeInuse
      logger.debug "#{vol[:name]} async remove: not removing; volume still in use"
    rescue Blockbridge::CommandError => e
      logger.debug "#{vol[:name]} async remove: #{e.message}"
      if e.message.include? "not found"
        vol_cache_rm(vol[:name])
      end
      raise
    end

    def volume_cache_monitor
      new_cache_version = cache_version_lookup
      return unless new_cache_version != cache_version
      logger.info "Validating volume cache"
      revalidate = false
      vol_cache_foreach do |v, vol|
        volume_invalidate(vol[:name]) unless (vol_info = bb_lookup_vol_info(vol))
        revalidate = true if vol[:deleted]
        volume_async_remove(vol, vol_info, vol[:env]) if vol[:deleted]
      end
      @cache_version = new_cache_version unless revalidate
    end

    def volume_cache_monitor_run
      volume_cache_monitor unless @api_status == :offline
    rescue Excon::Error => e
      logger.error "cache monitor request failed: #{e.message.chomp.squeeze("\n")}"
    rescue => e
      msg = e.message.chomp.squeeze("\n")
      msg.each_line do |m| logger.error "cache monitor: #{m.chomp}" end
      e.backtrace.each do |b| logger.error(b) end
    end

    def volume_api_status
      bbapi.status.authorization
      logger.info "STATUS: online" unless api_status == :online
      @api_status   = :online
      @api_syndrome = nil
    rescue => e
      syndrome = e.message.chomp.squeeze("\n")
      logger.info "STATUS: offline (#{syndrome})" unless api_status == :offline &&
                                                         api_syndrome == syndrome
      @api_status   = :offline
      @api_syndrome = syndrome
    end
  end
end
