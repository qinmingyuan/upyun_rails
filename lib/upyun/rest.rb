require 'httpx'
require 'open-uri'

module Upyun
  class Rest
    include Utils

    attr_reader :options
    def initialize(bucket, operator, password, options={timeout: 60}, endpoint = Upyun::ED_AUTO)
      @bucket = bucket
      @operator = operator
      @password = password
      @options = options
      @endpoint = endpoint
    end

    def put(path, file, headers = {})
      if file.is_a?(StringIO)
        body = file.read
      elsif file.respond_to?(:read)
        body = IO.binread(file)
      else
        body = file
      end
      options = { body: body, length: size(file), headers: headers }

      # If the type of current bucket is Picture,
      # put an image maybe return a set of headers
      # represent the image's metadata
      # x-upyun-width
      # x-upyun-height
      # x-upyun-frames
      # x-upyun-file-type
      res = request(:put, path, options) do |hds|
        hds.select { |k| k.to_s.match(/^x_upyun_/i) }.reduce({}) do |memo, (k, v)|
          memo.merge!({k[8..-1].to_sym => /^\d+$/.match(v) ? v.to_i : v})
        end
      end

      res == {} ? true : res
    ensure
      file.close if file.respond_to?(:close)
    end

    def get(path, savepath = nil, headers = {})
      res = request('GET', path, headers: headers)
      return res if res.is_a?(Hash) || !savepath

      dir = File.dirname(savepath)
      FileUtils.mkdir_p(dir) unless File.directory?(dir)
      File.write(savepath, res)
    end

    def getinfo(path)
      request(:head, path) do |hds|
        #  File info:
        #  x-upyun-file-type
        #  x-upyun-file-size
        #  x-upyun-file-date
        hds.select { |k| k.to_s.match(/^x_upyun_file/i) }.reduce({}) do |memo, (k, v)|
          memo.merge!({k[8..-1].to_sym => /^\d+$/.match(v) ? v.to_i : v})
        end
      end
    end

    alias :head :getinfo

    def delete(path)
      request(:delete, path)
    end

    def mkdir(path)
      request(:post, path, {headers: {folder: true}})
    end

    def getlist(path='/')
      res = request(:get, path)
      return res if res.is_a?(Hash)

      res.split("\n").map do |f|
        attrs = f.split("\t")
        {
          name: attrs[0],
          type: attrs[1] == 'N' ? :file : :folder,
          length: attrs[2].to_i,
          last_modified: attrs[3].to_i
        }
      end
    end

    def usage
      res = request(:get, '/', {query: 'usage'})
      return res if res.is_a?(Hash)

      # RestClient has a bug, body.to_i returns the code instead of body,
      # see more on https://github.com/rest-client/rest-client/pull/103
      res.dup.to_i
    end

    private
    def fullpath(path)
      "/#{@bucket}#{path.start_with?('/') ? path : '/' + path}"
    end

    def request(method, path, options = {}, &block)
      fullpath = fullpath(path)
      query = options[:query]
      fullpath_query = "#{fullpath}#{query.nil? ? '' : '?' + query}"
      headers = options[:headers] || {}
      x = options[:body].present? ? Digest::MD5.hexdigest(options[:body]) : ''
      date = Time.now.utc.strftime('%a, %d %b %Y %H:%M:%S GMT')
      headers.merge!(
        'Date' => date,
        'Content-MD5' => x,
        'Authorization' => sign(method, fullpath, date, x)
      )

      if [:post, :patch, :put].include? method
        body = options[:body].nil? ? '' : options[:body]
        rest_client.request(method, fullpath, body, headers: headers) do |res|
          if res.code >= 200 && res.code < 300
            block_given? ? yield(res.headers) : true
          else
            {
              request_id: res.headers[:x_request_id],
              error: {code: res.code, message: res.body}
            }
          end
        end
      else
        binding.b
        rest_client.request(method, fullpath, headers: headers) do |res|
          if res.code >= 200 && res.code < 300
            case method
            when :get
              res.json
            when :head
              yield(res.headers)
            else
              true
            end
          else
          {
            request_id: res.headers[:x_request_id],
            error: {
              code: res.code,
              message: res.body
            }
          }
          end
        end
      end
    end

    def rest_client
      @rest_client ||= HTTPX.with(origin: "https://#{@endpoint}", debug: STDERR, **options)
    end

    def sign(method, path, date, md5)
      sign = [method.to_s.upcase, path, date, md5.presence].compact.join('&')
      puts "#{sign}"
      "UPYUN #{@operator}:#{Utils.hmac_sha1(Digest::MD5.hexdigest(@password), sign)}"
    end

    def size(param)
      if param.respond_to?(:size)
        param.size
      elsif param.is_a?(IO)
        param.stat.size
      end
    end

  end
end
