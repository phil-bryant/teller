#! /usr/bin/env python3
from t_c_type import APIClient
from t_so import SubObject

class APIClient(APIClient):
    @classmethod
    def main(api_client_class: APIClient):
        so1 = SubObject(api_client_class())
        print(f"so1 = {so1}")
        so2 = SubObject(api_client_class())
        print(f"so2 = {so2}")
        so3 = SubObject([])
        print(f"so3 = {so3}")
        so4 = SubObject(so3._api_client, [{"key": "value"}])
        print(f"so4 = {so4}")

if __name__ == "__main__":
    APIClient.main()