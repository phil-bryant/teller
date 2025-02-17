from typing import Annotated

class Example:
    # Class variable with Annotated - WILL be in __annotations__
    class_var: Annotated[str, {"metadata": "collected"}] = "class"
    
    def __init__(self):
        # Instance variable with Annotated - will NOT be in __annotations__
        self.instance_var: Annotated[str, {"metadata": "discarded"}] = "instance"

    def print_annotations(self):
        print("Class __annotations__:", self.__class__.__annotations__)
        print("Instance __dict__:", self.__dict__)

if __name__ == "__main__":
    e = Example()
    e.print_annotations() 