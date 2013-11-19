class Provider < ActiveRecord::Base
  serialize :scopes_supported, JSON

  has_many :open_ids
  belongs_to :account

  validates :issuer,                 presence: true, uniqueness: {allow_nil: true}
  validates :name,                   presence: true
  validates :identifier,             presence: {if: :registered?}
  validates :authorization_endpoint, presence: {if: :registered?}
  validates :token_endpoint,         presence: {if: :registered?}
  validates :userinfo_endpoint,     presence: {if: :registered?}

  scope :dynamic,  where(dynamic: true)
  scope :listable, where(dynamic: false)
  scope :valid, lambda {
    where {
      (expires_at == nil) |
      (expires_at >= Time.now.utc)
    }
  }

  def expired?
    expires_at.try(:past?)
  end

  def registered?
    identifier.present? && !expired?
  end

  def config
    @config ||= OpenIDConnect::Discovery::Provider::Config.discover! issuer
  end

  def register!(redirect_uri)
    begin
        jwkset = OpenIDConnect.http_client.get_content(config.jwks_uri)
    rescue
        jwkset = nil
    end

    client = OpenIDConnect::Client::Registrar.new(
      config.registration_endpoint,
      client_name: 'NOV RP',
      application_type: 'web',
      redirect_uris: [redirect_uri],
      subject_type: 'pairwise'
    ).register!
    self.attributes = {
      identifier:             client.identifier,
      secret:                 client.secret,
      scope:                  config.scopes_supported,
      authorization_endpoint: config.authorization_endpoint,
      token_endpoint:         config.token_endpoint,
      userinfo_endpoint:      config.userinfo_endpoint,
      jwks_uri:               config.jwks_uri,
      jwkset:                 jwkset,           
      dynamic:                true,
      expires_at:             client.expires_in.try(:from_now)
    }
    save!
  end

  def self.discover!(host)
    #: for the case in which the flow is implicit ,
    #: and OpenID Configration + Client Registration have been manually finished,
    #: search "host" as "iss"
    begin
        issuer = OpenIDConnect::Discovery::Provider.discover!(host).issuer
    rescue
        issuer = host
    end

    if provider = find_by_issuer(issuer)
      provider
    else
      create(
        issuer: issuer,
        name: host
      )
    end
  end

  def as_json(options = {})
    [
      :identifier, :secret, :scope, :host, :scheme, :jwks_uri,
      :authorization_endpoint, :token_endpoint, :userinfo_endpoint
    ].inject({}) do |hash, key|
      hash.merge!(
        key => self.send(key)
      )
    end
  end

  def client
    @client ||= OpenIDConnect::Client.new as_json
  end

  def authorization_uri(redirect_uri, nonce, response_type = :code, scope = [:openid, :email, :profile, :address])
    client.redirect_uri = redirect_uri
    client.authorization_uri(
      response_type: response_type,
      nonce: nonce,
      state: nonce,
      scope: scope,
      # scope: [:openid, :profile, :address, :email, :address, :phone],
      # request: OpenIDConnect::RequestObject.new(
      #   id_token: {
      #     max_age: 10,
      #     claims: {
      #       auth_time: nil,
      #       acr: {
      #         values: ['0', '1', '2']
     #       }
      #     }
      #   },
      #   userinfo: {
      #     claims: {
      #       name: :required,
      #       email: :optional
      #     }
      #   }
      # ).to_jwt(client.secret, :HS256)
    )
  end


  def public_key
    if jwkset
      #: if jwkset is previsouly stored to this provider, use this jwkset.
      public_keys.first 
    else
      #: Otherwise,dynamically fetched from jku.
      config.public_keys.first
    end
  end
  
  def jwks
    @jwks ||= JSON.parse( jwkset ).with_indifferent_access
    JSON::JWK::Set.new @jwks[:keys]
  end 

  def public_keys
    @public_keys ||= jwks.collect do |jwk|
      JSON::JWK.decode jwk
    end
  end

  def decode_id(id_token)
    OpenIDConnect::ResponseObject::IdToken.decode id_token, public_key
  end

  def authenticate(redirect_uri, code, nonce)
    client.redirect_uri = redirect_uri
    client.authorization_code = code
    access_token = client.access_token!
    _id_token_ = decode_id access_token.id_token
    _id_token_.verify!(
      issuer: issuer,
      client_id: identifier,
      nonce: nonce
    )
    open_id = self.open_ids.find_or_initialize_by_identifier _id_token_.subject
    open_id.access_token, open_id.id_token = access_token.access_token, access_token.id_token
    open_id.save!
    open_id.account || Account.create!(open_id: open_id)
  end
end
