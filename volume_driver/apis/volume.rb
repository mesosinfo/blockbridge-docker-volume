# Copyright (c) 2015-2017, Blockbridge Networks LLC.  All rights reserved.
# Use of this source code is governed by a BSD-style license, found
# in the LICENSE file.

class API::Volume < Grape::API
  prefix 'volume'

  desc 'Create a volume'
  params do
    requires :name,         type: String,  desc: 'volume name'
    optional :profile,      type: String,  desc: 'volume profile'
    optional :user,         type: String,  desc: 'volume user (owner)'
    optional :capacity,     type: String,  desc: 'volume capacity'
    optional :type,         type: String,  desc: 'volume type'
    optional :iops,         type: Integer, desc: 'volume provisioning IOPS (QoS)'
    optional :transport,    type: String,  desc: 'specify transport security (tls, insecure)', transport_type: true
    optional :otp,          type: String,  desc: 'volume one time password (OTP)'
    optional :access_token, type: String,  desc: 'API access token for user authentication'
    optional :from_backup,  type: String,  desc: 'create volume from backup'
  end
  post do
    status 201
    synchronize do
      volume_create
      body(volume_info)
    end
  end

  desc 'List all volumes'
  get do
    body(volume_lookup_all)
  end

  route_param :name do
    desc "Show a volume"
    get do
      body(volume_lookup)
    end

    desc 'Delete a volume'
    delete do
      status 204
      synchronize do
        volume_remove
      end
    end

    resource :backup do
      desc 'Backup a volume'
      params do
        optional :backup_name, type: String, desc: 'backup name'
        optional :s3, type: String, desc: 'object store name'
      end
      put do
        status 201
        synchronize do
          body(volume_backup)
        end
      end
    end
  end

  route :any, '*path' do
    error!({ Error: 'Volume not found' }, 404)
  end
end
