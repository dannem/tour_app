from fastapi import FastAPI

# Create an instance of the FastAPI class
app = FastAPI()


# Define a "route" or "endpoint" for the root URL
@app.get("/")
def read_root():
    return {"message": "Welcome to the Tour App API!"}


# Define a new endpoint to get a list of tours
@app.get("/tours")
def get_tours():
    # In the future, this will fetch data from a database.
    # For now, we'll just return some sample "dummy" data.
    return [
        {"id": 1, "name": "Historic Downtown Walk"},
        {"id": 2, "name": "University Campus Tour"},
    ]
