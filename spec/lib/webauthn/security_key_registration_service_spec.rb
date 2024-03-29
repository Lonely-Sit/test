# frozen_string_literal: true
require "discourse_webauthn"
require "webauthn/security_key_registration_service"

RSpec.describe DiscourseWebauthn::SecurityKeyRegistrationService do
  subject(:service) { described_class.new(current_user, params, challenge_params) }

  let(:client_data_challenge) { Base64.encode64(challenge) }
  let(:client_data_webauthn_type) { "webauthn.create" }
  let(:client_data_origin) { "http://localhost:3000" }
  let(:client_data_param) do
    {
      challenge: client_data_challenge,
      type: client_data_webauthn_type,
      origin: client_data_origin,
    }
  end
  ##
  # This attestation object was sourced by manually registering
  # a key with `navigator.credentials.create` and capturing the
  # results in localhost.
  let(:attestation) do
    "o2NmbXRkbm9uZWdhdHRTdG10oGhhdXRoRGF0YVjESZYN5YgOjGh0NBcPZHZgW4/krrmihjLHmVzzuoMdl2NBAAAAAAAAAAAAAAAAAAAAAAAAAAAAQFmvayWc8OPJ4jj4sevfxBmvUglDMZrFalyokYrdnqOVvudC0lQialaGQv72eBzJM2Qn1GfJI7lpBgFJMprisLSlAQIDJiABIVgg+23/BZux7LK0/KQgCiQGtdr51ar+vfTtHWpRtN17gOwiWCBstV918mugVBexg/rdZjTs0wN/upHFoyBiAJCaGVD8OA=="
  end
  let(:params) do
    {
      clientData: Base64.encode64(client_data_param.to_json),
      attestation: attestation,
      name: "My Yubikey",
    }
  end
  ##
  # The above attestation was generated in localhost; Discourse.current_hostname
  # returns test.localhost which we do not want
  let(:rp_id) { "localhost" }
  let(:challenge_params) { { challenge: challenge, rp_id: rp_id, origin: "http://localhost:3000" } }
  let(:challenge) { "f1e04530f34a1b6a08d032d8550e23eb8330be04e4166008f26c0e1b42ad" }
  let(:current_user) { Fabricate(:user) }

  context "when the client data webauthn type is not webauthn.create" do
    let(:client_data_webauthn_type) { "webauthn.explode" }

    it "raises an InvalidTypeError" do
      expect { service.register_second_factor_security_key }.to raise_error(
        DiscourseWebauthn::InvalidTypeError,
        I18n.t("webauthn.validation.invalid_type_error"),
      )
    end
  end

  context "when the decoded challenge does not match the original challenge provided by the server" do
    let(:client_data_challenge) { Base64.encode64("invalid challenge") }

    it "raises a ChallengeMismatchError" do
      expect { service.register_second_factor_security_key }.to raise_error(
        DiscourseWebauthn::ChallengeMismatchError,
        I18n.t("webauthn.validation.challenge_mismatch_error"),
      )
    end
  end

  context "when the origin of the client data does not match the server origin" do
    let(:client_data_origin) { "https://someothersite.com" }

    it "raises a InvalidOriginError" do
      expect { service.register_second_factor_security_key }.to raise_error(
        DiscourseWebauthn::InvalidOriginError,
        I18n.t("webauthn.validation.invalid_origin_error"),
      )
    end
  end

  context "when the sha256 hash of the relaying party ID does not match the one in attestation.authData" do
    let(:rp_id) { "bad_rp_id" }

    it "raises a InvalidRelyingPartyIdError" do
      expect { service.register_second_factor_security_key }.to raise_error(
        DiscourseWebauthn::InvalidRelyingPartyIdError,
        I18n.t("webauthn.validation.invalid_relying_party_id_error"),
      )
    end
  end

  context "when the public key algorithm is not supported by the server" do
    before do
      @original_supported_alg_value = DiscourseWebauthn::SUPPORTED_ALGORITHMS
      silence_warnings { DiscourseWebauthn::SUPPORTED_ALGORITHMS = [-999] }
    end

    it "raises a UnsupportedPublicKeyAlgorithmError" do
      expect { service.register_second_factor_security_key }.to raise_error(
        DiscourseWebauthn::UnsupportedPublicKeyAlgorithmError,
        I18n.t("webauthn.validation.unsupported_public_key_algorithm_error"),
      )
    end

    after do
      silence_warnings { DiscourseWebauthn::SUPPORTED_ALGORITHMS = @original_supported_alg_value }
    end
  end

  context "when the attestation format is not supported" do
    before do
      @original_supported_alg_value = DiscourseWebauthn::VALID_ATTESTATION_FORMATS
      silence_warnings { DiscourseWebauthn::VALID_ATTESTATION_FORMATS = ["err"] }
    end

    it "raises a UnsupportedAttestationFormatError" do
      expect { service.register_second_factor_security_key }.to raise_error(
        DiscourseWebauthn::UnsupportedAttestationFormatError,
        I18n.t("webauthn.validation.unsupported_attestation_format_error"),
      )
    end

    after do
      silence_warnings do
        DiscourseWebauthn::VALID_ATTESTATION_FORMATS = @original_supported_alg_value
      end
    end
  end

  context "when the credential id is already in use for any user" do
    it "raises a CredentialIdInUseError" do
      # register the key to the current user
      security_key = service.register_second_factor_security_key

      # update the key to be on a different user
      other_user = Fabricate(:user)
      security_key.update(user: other_user)

      # error!
      expect { service.register_second_factor_security_key }.to raise_error(
        DiscourseWebauthn::CredentialIdInUseError,
        I18n.t("webauthn.validation.credential_id_in_use_error"),
      )
    end
  end

  context "when the attestation data is malformed" do
    let(:attestation) do
      "blah/krrmihjLHmVzzuoMdl2NBAAAAAAAAAAAAAAAAAAAAAAAAAAAAQFmvayWc8OPJ4jj4sevfxBmvUglDMZrFalyokYrdnqOVvudC0lQialaGQv72eBzJM2Qn1GfJI7lpBgFJMprisLSlAQIDJiABIVgg+23/BZux7LK0/KQgCiQGtdr51ar+vfTtHWpRtN17gOwiWCBstV918mugVBexg/rdZjTs0wN/upHFoyBiAJCaGVD8OA=="
    end

    it "raises a MalformedAttestationError" do
      expect { service.register_second_factor_security_key }.to raise_error(
        DiscourseWebauthn::MalformedAttestationError,
        I18n.t("webauthn.validation.malformed_attestation_error"),
      )
    end
  end
end
