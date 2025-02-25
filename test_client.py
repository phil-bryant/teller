#! /usr/bin/env python3
print()

from test_client_type import APIClient
from test_sub_object import SubObj

class APIClient(object):
    @classmethod
    def main(cls):
        s1_1 = SubObj(cls())

if __name__ == "__main__":
    APIClient.main()