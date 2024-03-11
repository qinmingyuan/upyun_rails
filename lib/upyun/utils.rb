require 'digest/md5'

module Upyun
  module Utils
    extend self

    def md5(str)
      Digest::MD5.hexdigest(str)
    end

    def hmac_sha1(key, str)
      Base64.urlsafe_encode64(OpenSSL::HMAC.digest('sha1', key, str))
    end

    def included(receiver)
      receiver.send(:define_method, :endpoint) { @endpoint }
      receiver.send(:define_method, :endpoint=) do |ep|
        unless Upyun::ED_LIST.member?(ep)
          raise ArgumentError, "Valid endpoints are: #{Upyun::ED_LIST}"
        end
        @endpoint = ep
      end
    end

  end
end
