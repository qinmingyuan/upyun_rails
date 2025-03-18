require 'httpx'
require 'open-uri'

module Upyun
  class Rest
    include Utils

    def initialize(operator, password, endpoint: Upyun::ED_AUTO, debug: false)
      @operator = operator
      @password = password
      if debug
        @httpx = HTTPX.with(origin: "https://#{endpoint}", debug: STDOUT, debug_level: 1, **options)
      else
        @httpx = HTTPX.with(origin: "https://#{endpoint}", **options)
      end
    end

    def put_chunk(path, file, per:, **headers)
      r = request('PUT', path, headers: {
        'X-Upyun-Multi-Disorder' => true,
        'X-Upyun-Multi-Stage' => 'initiate',
        'X-Upyun-Multi-Length' => file.size,
        'X-Upyun-Multi-Part-Size' => per,
        'X-Upyun-Multi-Type' => headers[:content_type],
        'Content-Length' => 0,
        **headers
      })
      if r.status == 204
        uuid = r.headers['x-upyun-multi-uuid']
      else
        raise r.body.to_s
      end

      chunk_index = 0
      while chunk = file.read(per)
        request('PUT', path, body: chunk, headers: {
          'X-Upyun-Multi-Stage' => 'upload',
          'X-Upyun-Multi-Uuid' => uuid,
          'X-Upyun-Part-Id' => chunk_index,
          'Content-Length' => chunk.size,
          **headers
        })
        chunk_index += 1
      end

      request('PUT', path, headers: {
        'X-Upyun-Multi-Stage' => 'complete',
        'X-Upyun-Multi-Uuid' => uuid,
        'Content-Length' => 0
      })
    ensure
      file.close
    end

    def put(path, file, **headers)
      if file.is_a?(StringIO)
        body = file.read
      elsif file.respond_to?(:read)
        body = IO.binread(file)
      else
        body = file
      end
      options = {
        body: body,
        headers: {
          'Content-Length' => size(file),
          **headers
        }
      }


      request('PUT', path, options) do |hds|
        hds.select { |k| k.to_s.match(/^x_upyun_/i) }.reduce({}) do |memo, (k, v)|
          memo.merge!({k[8..-1].to_sym => /^\d+$/.match(v) ? v.to_i : v})
        end
      end
    ensure
      file.close if file.respond_to?(:close)
    end

    def get(path, savepath = nil, headers = {})
      res = request('GET', path, headers: headers)
      if savepath
        dir = File.dirname(savepath)
        FileUtils.mkdir_p(dir) unless File.directory?(dir)
        File.write(savepath, res)
      else
        res.read
      end
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

    def delete(path)
      request('DELETE', path)
    end

    def mkdir(path)
      request('POST', path, {headers: {folder: true}})
    end

    def getlist(path='/')
      res = request('GET', path).json
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
      request('GET', '/?usage')
    end

    private
    def request(method, path, options = {}, &block)
      headers = options[:headers] || {}
      x = options[:body].present? ? Digest::MD5.hexdigest(options[:body]) : ''
      date = Time.now.utc.strftime('%a, %d %b %Y %H:%M:%S GMT')
      headers.transform_keys!(&->(k){ k.to_s.dasherize })
      headers.merge!(
        'Date' => date,
        'Authorization' => sign(method, path, date)
      )

      @httpx.request(method, path, headers: headers, **options.slice(:body, :params))
    end

    def sign(method, path, date)
      sign = [method.to_s.upcase, path, date].join('&')
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
