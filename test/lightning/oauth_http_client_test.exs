defmodule Lightning.AuthProviders.OauthHTTPClientTest do
  use ExUnit.Case, async: true
  import Mox

  setup :verify_on_exit!

  describe "fetch_token/2" do
    test "fetches token successfully" do
      client = %{
        client_id: "id",
        client_secret: "secret",
        token_endpoint: "http://example.com/token"
      }

      code = "authcode123"
      response_body = %{"access_token" => "token123", "token_type" => "bearer"}

      expect(Lightning.AuthProviders.OauthHTTPClient.Mock, :call, fn
        env, _opts
        when env.method == :post and env.url == "http://example.com/token" ->
          assert env.body ==
                   %{
                     client_id: "id",
                     client_secret: "secret",
                     code: "authcode123",
                     grant_type: "authorization_code",
                     redirect_uri: "http://localhost:4002/authenticate/callback"
                   }
                   |> URI.encode_query()

          {:ok, %Tesla.Env{status: 200, body: Jason.encode!(response_body)}}
      end)

      result =
        Lightning.AuthProviders.OauthHTTPClient.fetch_token(client, code)

      assert {:ok, response_body} == result
    end
  end

  describe "refresh_token/4" do
    test "refreshes the token successfully" do
      client_id = "id"
      client_secret = "secret"
      refresh_token = "validRefreshToken"
      token_endpoint = "http://example.com/refresh"

      response_body = %{
        "access_token" => "newToken123",
        "token_type" => "bearer"
      }

      expect(Lightning.AuthProviders.OauthHTTPClient.Mock, :call, fn
        env, _opts
        when env.method == :post and env.url == token_endpoint ->
          assert env.body ==
                   %{
                     client_id: client_id,
                     client_secret: client_secret,
                     refresh_token: refresh_token,
                     grant_type: "refresh_token"
                   }
                   |> URI.encode_query()

          {:ok, %Tesla.Env{status: 200, body: Jason.encode!(response_body)}}
      end)

      result =
        Lightning.AuthProviders.OauthHTTPClient.refresh_token(
          client_id,
          client_secret,
          refresh_token,
          token_endpoint
        )

      assert {:ok, response_body} == result
    end

    test "handles error when refresh token is invalid" do
      client_id = "id"
      client_secret = "secret"
      refresh_token = "invalidRefreshToken"
      token_endpoint = "http://example.com/refresh"

      expect(Lightning.AuthProviders.OauthHTTPClient.Mock, :call, fn
        env, _opts
        when env.method == :post and env.url == token_endpoint ->
          {:ok, %Tesla.Env{status: 400, body: "Invalid refresh token"}}
      end)

      result =
        Lightning.AuthProviders.OauthHTTPClient.refresh_token(
          client_id,
          client_secret,
          refresh_token,
          token_endpoint
        )

      assert {:error, "\"Invalid refresh token\""} ==
               result
    end
  end

  describe "still_fresh/3" do
    test "returns true if the token is still fresh based on expires_in" do
      current_time = DateTime.utc_now()
      future_time = DateTime.add(current_time, 10 * 60, :second)
      params = %{"expires_in" => DateTime.to_unix(future_time)}

      assert Lightning.AuthProviders.OauthHTTPClient.still_fresh(
               params,
               5,
               :minute
             )
    end

    test "returns false if the token has expired" do
      expired_time =
        DateTime.utc_now() |> DateTime.add(-30, :minute)

      params = %{"expires_at" => DateTime.to_unix(expired_time)}

      refute Lightning.AuthProviders.OauthHTTPClient.still_fresh(
               params,
               5,
               :minute
             )
    end

    test "returns false if the token has a nil expires_at / expires_in value" do
      ~w(expires_at expires_in)
      |> Enum.each(fn key ->
        params = %{key => nil}

        refute Lightning.AuthProviders.OauthHTTPClient.still_fresh(
                 params,
                 5,
                 :minute
               )
      end)
    end

    test "handles invalid expiration data" do
      params = %{}

      assert {:error, "No valid expiration data found"} ===
               Lightning.AuthProviders.OauthHTTPClient.still_fresh(
                 params,
                 5,
                 :minute
               )
    end
  end

  describe "generate_authorize_url/3" do
    test "generates a correct authorization URL with default parameters" do
      base_url = "http://example.com/auth"
      client_id = "client123"
      custom_params = [scope: "email", state: "xyz"]

      expected_params = [
        access_type: "offline",
        client_id: "client123",
        prompt: "consent",
        redirect_uri: "http://localhost:4002/authenticate/callback",
        response_type: "code",
        scope: "email",
        state: "xyz"
      ]

      expected_url = "#{base_url}?#{URI.encode_query(expected_params)}"

      assert expected_url ===
               Lightning.AuthProviders.OauthHTTPClient.generate_authorize_url(
                 base_url,
                 client_id,
                 custom_params
               )
    end
  end

  describe "fetch_userinfo/2" do
    test "fetches user information successfully" do
      token = "validAccessToken"
      userinfo_endpoint = "http://example.com/userinfo"
      response_body = %{"user_id" => "123", "name" => "John Doe"}

      expect(Lightning.AuthProviders.OauthHTTPClient.Mock, :call, fn
        env, _opts
        when env.method == :get and env.url == userinfo_endpoint ->
          assert Enum.any?(env.headers, fn {k, v} ->
                   k == "Authorization" and v == "Bearer #{token}"
                 end)

          {:ok, %Tesla.Env{status: 200, body: Jason.encode!(response_body)}}
      end)

      result =
        Lightning.AuthProviders.OauthHTTPClient.fetch_userinfo(
          token,
          userinfo_endpoint
        )

      assert {:ok, response_body} == result
    end

    test "handles error when access token is expired" do
      token = "expiredAccessToken"
      userinfo_endpoint = "http://example.com/userinfo"

      expect(Lightning.AuthProviders.OauthHTTPClient.Mock, :call, fn
        env, _opts
        when env.method == :get and env.url == userinfo_endpoint ->
          {:ok, %Tesla.Env{status: 401, body: "Token expired"}}
      end)

      result =
        Lightning.AuthProviders.OauthHTTPClient.fetch_userinfo(
          token,
          userinfo_endpoint
        )

      assert {:error, "\"Token expired\""} == result
    end

    test "handles http request error" do
      token = "accessToken"
      userinfo_endpoint = "http://example.com/userinfo"

      expect(Lightning.AuthProviders.OauthHTTPClient.Mock, :call, fn
        env, _opts
        when env.method == :get and env.url == userinfo_endpoint ->
          {:error, :nxdomain}
      end)

      result =
        Lightning.AuthProviders.OauthHTTPClient.fetch_userinfo(
          token,
          userinfo_endpoint
        )

      assert {:error, ":nxdomain"} == result
    end
  end
end